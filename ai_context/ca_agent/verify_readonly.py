"""以 data-chatbox-ro 的身分驗證：讀得到 news_dept_social，任何寫入都被拒。

寫入測試只針對一張臨時探測表 news_dept_social.zz_chatbox_ro_probe（由操作者自己的帳號建立、
測完刪除），不會碰到正式的 view。

需要：操作者在 SA 上有 roles/iam.serviceAccountTokenCreator（setup_readonly_access.py 會設定）。

用法（在 taiwanplus_dbt/ 下）：
    python ai_context/ca_agent/verify_readonly.py
"""
import sys

from google.api_core import exceptions
from google.cloud import bigquery

from common import MAX_BILLED_BYTES as MAX_BYTES, PROJECT, sa_credentials

DATASET = "news_dept_social"
PROBE = f"{PROJECT}.{DATASET}.zz_chatbox_ro_probe"

READ_TABLES = [
    "agg_news_dept_daily_traffic_monthly",
    "agg_news_dept_social_monthly",
    "fct_daily_traffic",
    "fct_social_post_performance",
    "platform_metric_glossary",
]

WRITE_SQL = {
    "INSERT": f"INSERT INTO `{PROBE}` (x) VALUES (2)",
    "UPDATE": f"UPDATE `{PROBE}` SET x = 3 WHERE TRUE",
    "DELETE": f"DELETE FROM `{PROBE}` WHERE TRUE",
    "DROP TABLE": f"DROP TABLE `{PROBE}`",
    "CREATE TABLE": f"CREATE TABLE `{PROJECT}.{DATASET}.zz_chatbox_ro_new` AS SELECT 1 AS x",
    "CREATE VIEW": f"CREATE VIEW `{PROJECT}.{DATASET}.zz_chatbox_ro_view` AS SELECT 1 AS x",
    "CREATE SCHEMA": f"CREATE SCHEMA `{PROJECT}.zz_chatbox_ro_dataset`",
}


def main():
    me = bigquery.Client(project=PROJECT)
    sa = bigquery.Client(project=PROJECT, credentials=sa_credentials())
    cfg = bigquery.QueryJobConfig(maximum_bytes_billed=MAX_BYTES, labels={"purpose": "chatbox-ro-verify"})
    results = []

    me.query(f"CREATE OR REPLACE TABLE `{PROBE}` AS SELECT 1 AS x").result()
    try:
        print("== 讀取（應該成功）")
        for t in READ_TABLES:
            try:
                n = list(sa.query(f"SELECT COUNT(*) AS n FROM `{PROJECT}.{DATASET}.{t}`", job_config=cfg).result())[0].n
                results.append((f"SELECT {t}", True, f"{n:,} 列"))
            except exceptions.GoogleAPICallError as e:
                results.append((f"SELECT {t}", False, _short(e)))

        print("== 寫入（應該全部被拒）")
        for name, sql in WRITE_SQL.items():
            try:
                sa.query(sql, job_config=cfg).result()
                results.append((f"{name}", False, "竟然成功了！"))
            except (exceptions.Forbidden, exceptions.BadRequest, exceptions.NotFound) as e:
                results.append((f"{name}", True, f"被拒：{_short(e)}"))

        for name, fn in {
            "API delete_table": lambda: sa.delete_table(PROBE),
            "API create_dataset": lambda: sa.create_dataset(f"{PROJECT}.zz_chatbox_ro_dataset2"),
            "API insert_rows": lambda: _insert_rows(sa),
        }.items():
            try:
                fn()
                results.append((name, False, "竟然成功了！"))
            except (exceptions.Forbidden, exceptions.BadRequest, exceptions.NotFound, PermissionError) as e:
                results.append((name, True, f"被拒：{_short(e)}"))
    finally:
        # 不論結果，用操作者帳號清掉探測物件
        for obj in ("zz_chatbox_ro_probe", "zz_chatbox_ro_new", "zz_chatbox_ro_view"):
            me.delete_table(f"{PROJECT}.{DATASET}.{obj}", not_found_ok=True)
        for d in ("zz_chatbox_ro_dataset", "zz_chatbox_ro_dataset2"):
            me.delete_dataset(f"{PROJECT}.{d}", not_found_ok=True)

    ok_all = True
    for name, ok, detail in results:
        ok_all &= ok
        print(f"  {'PASS' if ok else 'FAIL'}  {name:<45} {detail}")
    print("\n結果：" + ("全部通過" if ok_all else "有失敗項目"))
    sys.exit(0 if ok_all else 1)


def _insert_rows(client):
    errors = client.insert_rows_json(PROBE, [{"x": 9}])
    if errors:
        raise PermissionError(str(errors))


def _short(e):
    msg = getattr(e, "message", str(e))
    return msg.splitlines()[0][:110]


if __name__ == "__main__":
    main()
