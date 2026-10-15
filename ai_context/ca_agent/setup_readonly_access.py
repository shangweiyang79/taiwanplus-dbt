"""建立 Data Chatbox 的唯讀 service account，並設定讓它查得到 news_dept_social 的 view。

預設只印出計畫，不做任何變更；加 --apply 才執行。
執行前會把每個要改的 dataset 目前的 ACL 備份到 ca_agent/acl_backup/<時間>/。

用法（在 taiwanplus_dbt/ 下）：
    python ai_context/ca_agent/setup_readonly_access.py             # 只看計畫
    python ai_context/ca_agent/setup_readonly_access.py --apply   # 可重複執行，已設定的會略過

權限設計（見 research/data_chatbox_and_bqml_forecast_research.md §3）：
- SA 只拿 bigquery.jobUser / geminidataanalytics.dataAgentUser / cloudaicompanion.user（專案層級）
  ＋ news_dept_social 的 READER。不給 bigquery.user、不給任何 editor。
- 底層讀取靠 authorized dataset：news_dept_social / dbt_internal 的 view 被授權讀底層 dataset。
"""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import time

from google.cloud import bigquery

PROJECT = "ivory-airfoil-418408"
SA_ID = "data-chatbox-ro"
SA_EMAIL = f"{SA_ID}@{PROJECT}.iam.gserviceaccount.com"
OPERATOR = "joy.yang@pts.org.tw"  # 跑評估腳本時要模擬 SA 的人

PROJECT_ROLES = [
    "roles/bigquery.jobUser",
    "roles/geminidataanalytics.dataAgentUser",
    "roles/cloudaicompanion.user",
]
READER_DATASETS = ["news_dept_social"]

# 底層 dataset -> 要授權哪些 dataset 的 view 來讀它（依 INFORMATION_SCHEMA.VIEWS 的實際引用整理）
AUTHORIZED = {
    # social_hub.vod_category（被 fct_social_post_performance 引用）會回頭讀 dbt_internal.stg_social_hub__post_map
    "dbt_internal": ["news_dept_social", "social_hub"],
    "social_hub": ["news_dept_social", "dbt_internal"],
    "Facebook_data": ["dbt_internal"],
    "Instagram_data": ["dbt_internal"],
    "X_data": ["dbt_internal"],
    "youtube_channel_summary": ["dbt_internal", "social_hub"],  # social_hub.vod_category 也讀它
    "youtube_taiwanplus_owner": ["dbt_internal"],
}
# 2026-10-15 實測：同 dataset 內的巢狀 view（dbt_internal 的 int -> stg、Instagram_data 的 view）
# 不需要自我授權；以上清單即為最小必要設定，verify_readonly.py 全部通過。
# 日後若 news_dept_social 的 view 引用新的 dataset，要把它加進這裡再重跑。

HERE = os.path.dirname(os.path.abspath(__file__))


def gcloud(*args, check=True, retries=5):
    """執行 gcloud；SA 剛建立時 IAM 需要幾秒同步，所以失敗會重試。"""
    cmd = [shutil.which("gcloud"), *args, "--billing-project", PROJECT, "--quiet"]
    print("   $ gcloud " + " ".join(args))
    for attempt in range(retries if check else 1):
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode == 0 or not check:
            return r
        print(f"     失敗（第 {attempt + 1} 次），10 秒後重試：{r.stderr.strip().splitlines()[-1][:150]}")
        time.sleep(10)
    raise RuntimeError(r.stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="真的執行變更（預設只印計畫）")
    args = parser.parse_args()
    authorized = AUTHORIZED

    mode = "APPLY" if args.apply else "DRY-RUN（加 --apply 才會執行）"
    print(f"== 模式：{mode}\n")

    # 1. service account
    print(f"1. 建立 service account {SA_EMAIL}")
    if args.apply:
        r = gcloud("iam", "service-accounts", "describe", SA_EMAIL, "--project", PROJECT, check=False)
        if r.returncode == 0:
            print("   已存在，略過")
        else:
            gcloud("iam", "service-accounts", "create", SA_ID, "--project", PROJECT,
                   "--display-name", "Data Chatbox (read-only)",
                   "--description", "Conversational Analytics API 用的唯讀身分；只能讀 news_dept_social")

    # 2. 專案層級角色
    print("2. 專案層級角色")
    for role in PROJECT_ROLES:
        print(f"   + {role}")
        if args.apply:
            gcloud("projects", "add-iam-policy-binding", PROJECT,
                   "--member", f"serviceAccount:{SA_EMAIL}", "--role", role, "--condition", "None")

    # 3. 讓操作者可以模擬 SA（只針對這個 SA）
    print(f"3. {OPERATOR} 在這個 SA 上取得 roles/iam.serviceAccountTokenCreator")
    if args.apply:
        gcloud("iam", "service-accounts", "add-iam-policy-binding", SA_EMAIL, "--project", PROJECT,
               "--member", f"user:{OPERATOR}", "--role", "roles/iam.serviceAccountTokenCreator")

    # 4. dataset ACL
    client = bigquery.Client(project=PROJECT)
    backup_dir = os.path.join(HERE, "acl_backup", datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    targets = sorted(set(READER_DATASETS) | set(authorized))
    print("4. dataset ACL")
    for ds_id in targets:
        ds = client.get_dataset(f"{PROJECT}.{ds_id}")
        entries = list(ds.access_entries)
        new = []
        if ds_id in READER_DATASETS:
            e = bigquery.AccessEntry("READER", "userByEmail", SA_EMAIL)
            if not any(x.entity_type == "userByEmail" and x.entity_id == SA_EMAIL for x in entries):
                new.append(e)
                print(f"   {ds_id}: + READER {SA_EMAIL}")
        for src in authorized.get(ds_id, []):
            if _has_authorized_dataset(entries, src):
                continue
            new.append(bigquery.AccessEntry(None, "dataset", {
                "dataset": {"projectId": PROJECT, "datasetId": src},
                "targetTypes": ["VIEWS"],
            }))
            print(f"   {ds_id}: + authorized dataset {src}")
        if not new:
            print(f"   {ds_id}: 不需變更")
            continue
        if args.apply:
            os.makedirs(backup_dir, exist_ok=True)
            with open(os.path.join(backup_dir, f"{ds_id}.json"), "w", encoding="utf-8") as f:
                json.dump([x.to_api_repr() for x in entries], f, ensure_ascii=False, indent=2)
            ds.access_entries = entries + new
            client.update_dataset(ds, ["access_entries"])

    if args.apply:
        print(f"\n完成。原 ACL 備份在 {backup_dir}")


def _has_authorized_dataset(entries, src):
    for x in entries:
        if x.entity_type == "dataset" and (x.entity_id or {}).get("dataset", {}).get("datasetId") == src:
            return True
    return False


if __name__ == "__main__":
    main()
