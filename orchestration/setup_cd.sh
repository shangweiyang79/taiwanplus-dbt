#!/usr/bin/env bash
# 建立 CD（合併進 main 後自動部署）需要的 GCP 資源。可重複執行。
# 前提：已跑過 setup_gcp.sh 與 setup_youtube_chain.sh（WIF pool、dbt-daily-checks、youtube-owner-chain 都已存在）。
#
# 用法（在 repo 根目錄，帳號需為專案 owner）：
#   GCP_PROJECT=<gcp-project> bash orchestration/setup_cd.sh
#
# 建立的東西：
#   dbt-deployer SA  deploy / deploy-checks job 用（不需核准）。只能做這三件部署：
#     1. 推 dbt-daily-checks 映像、更新 job 用的映像
#     2. 部署 workflow youtube-owner-chain
#     3. 重建 youtube_channel_summary 裡的 refresh_* stored procedure（也要讀 youtube_taiwanplus_owner，建立時要驗證）
#     不能動 dbt 的 prod dataset。WIF 只讓 main 分支換成這個 SA。
#   dbt-prod SA      deploy-dbt job 用（要在 GitHub Environment prod 按核准）。dbt build --target prod：
#     可讀全部資料，只能寫 dbt 的三個 prod dataset。WIF 只讓 environment prod 換成這個 SA。
#
# PR、其他分支、fork 都拿不到部署權限。
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GCP_PROJECT:?請設定 GCP_PROJECT}"
REGION=asia-east1
GITHUB_REPO="${GITHUB_REPO:-shangweiyang79/taiwanplus-dbt}"
POOL=github
JOB=dbt-daily-checks
AR_REPO=cloud-run-source-deploy   # gcloud run deploy --source 自動建的 repo，現有映像也在這裡
# dbt 在 prod 寫入的 dataset，見 dbt_project.yml
PROD_DATASETS="dbt_internal news_dept_social social_hub"

P=(--project="$GCP_PROJECT" --billing-project="$GCP_PROJECT")
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" "${P[@]}" --format='value(projectNumber)')
DEPLOY_SA="dbt-deployer@$GCP_PROJECT.iam.gserviceaccount.com"
PROD_SA="dbt-prod@$GCP_PROJECT.iam.gserviceaccount.com"
RUNNER_SA="dbt-runner@$GCP_PROJECT.iam.gserviceaccount.com"
CHAIN_SA="yt-chain@$GCP_PROJECT.iam.gserviceaccount.com"
bq_sql() { bq --project_id="$GCP_PROJECT" --location="$REGION" query --use_legacy_sql=false --quiet "$@" >/dev/null; }

echo "== Service accounts =="
gcloud iam service-accounts describe "$DEPLOY_SA" "${P[@]}" >/dev/null 2>&1 ||
  gcloud iam service-accounts create dbt-deployer --display-name="dbt deployer" \
    --description="GitHub Actions deploy job (main only): daily-checks image, owner-chain workflow, refresh procedures" "${P[@]}"
gcloud iam service-accounts describe "$PROD_SA" "${P[@]}" >/dev/null 2>&1 ||
  gcloud iam service-accounts create dbt-prod --display-name="dbt prod build" \
    --description="GitHub Actions deploy-dbt job (environment prod, approved): dbt build --target prod" "${P[@]}"

echo "== 1. dbt-daily-checks 映像 =="
gcloud artifacts repositories add-iam-policy-binding "$AR_REPO" --location="$REGION" \
  --member="serviceAccount:$DEPLOY_SA" --role=roles/artifactregistry.writer "${P[@]}" >/dev/null
# 只綁在這個 job 上，碰不到其他 Cloud Run 服務（cf-* ingestion 等）
gcloud run jobs add-iam-policy-binding "$JOB" --region="$REGION" \
  --member="serviceAccount:$DEPLOY_SA" --role=roles/run.developer "${P[@]}" >/dev/null

echo "== 2. workflow youtube-owner-chain =="
gcloud projects add-iam-policy-binding "$GCP_PROJECT" --member="serviceAccount:$DEPLOY_SA" \
  --role=roles/workflows.editor --condition=None --quiet "${P[@]}" >/dev/null

# 更新 job / workflow 時要以它們的執行身分部署（actAs），只開這兩個 SA
for sa in "$RUNNER_SA" "$CHAIN_SA"; do
  gcloud iam service-accounts add-iam-policy-binding "$sa" --member="serviceAccount:$DEPLOY_SA" \
    --role=roles/iam.serviceAccountUser "${P[@]}" >/dev/null
done

echo "== 3. stored procedures =="
gcloud projects add-iam-policy-binding "$GCP_PROJECT" --member="serviceAccount:$DEPLOY_SA" \
  --role=roles/bigquery.jobUser --condition=None --quiet "${P[@]}" >/dev/null
# BigQuery 沒有「只能改 routine」的預設角色，只好給這個 dataset 的 dataEditor
bq_sql "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$GCP_PROJECT.youtube_channel_summary\` TO \"serviceAccount:$DEPLOY_SA\""
# CREATE PROCEDURE 會先驗證 procedure 本體（strict mode），部署者要讀得到裡面查的表。
# 不用 strict_mode=false 繞過：驗證能在部署時就抓到 SQL 寫錯，而不是等 workflow 呼叫才失敗。
bq_sql "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$GCP_PROJECT.youtube_taiwanplus_owner\` TO \"serviceAccount:$DEPLOY_SA\""

echo "== 4. dbt build --target prod =="
# 與 dbt-ci 相同的讀取權限：source 散在各平台的 dataset。readSessionUser 是 dbt Fusion 取查詢結果要的
for role in roles/bigquery.dataViewer roles/bigquery.jobUser roles/bigquery.readSessionUser; do
  gcloud projects add-iam-policy-binding "$GCP_PROJECT" --member="serviceAccount:$PROD_SA" --role="$role" \
    --condition=None --quiet "${P[@]}" >/dev/null
done
for ds in $PROD_DATASETS; do
  bq_sql "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$GCP_PROJECT.$ds\` TO \"serviceAccount:$PROD_SA\""
done

echo "== WIF =="
# provider 已把 google.subject 對應到 OIDC 的 sub。這個 repo 開了 GitHub 的 immutable subject，
# sub 會帶 owner 與 repo 的數字 ID：repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main。
# 好處是 repo 被刪掉、別人再用同名建立時換不到這些 SA。前綴可以這樣查：
#   curl -s https://api.github.com/repos/$GITHUB_REPO/actions/oidc/customization/sub
SUB_PREFIX=$(curl -sf "https://api.github.com/repos/$GITHUB_REPO/actions/oidc/customization/sub" |
  python -c "import sys,json; d=json.load(sys.stdin); print(d.get('sub_claim_prefix') or 'repo:$GITHUB_REPO')" | tr -d '\r')
SUBJECT="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/subject"
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" --role=roles/iam.workloadIdentityUser \
  --member="$SUBJECT/$SUB_PREFIX:ref:refs/heads/main" "${P[@]}" >/dev/null
echo "  $SUB_PREFIX:ref:refs/heads/main → $DEPLOY_SA"
# 用了 environment 的 job，sub 是 environment:<名稱>，不含分支。所以 GitHub 那邊的 environment
# 一定要設「只允許 main」，再加上必要審核者，才算只有 main 而且有人核准才能寫 prod。
gcloud iam service-accounts add-iam-policy-binding "$PROD_SA" --role=roles/iam.workloadIdentityUser \
  --member="$SUBJECT/$SUB_PREFIX:environment:prod" "${P[@]}" >/dev/null
echo "  $SUB_PREFIX:environment:prod → $PROD_SA"

cat <<EOF

完成。接著到 GitHub repo → Settings：
1. Secrets and variables → Actions 的 repository secret（已經有就略過）：
     GCP_DEPLOY_SERVICE_ACCOUNT   $DEPLOY_SA
2. Environments → New environment「prod」：
     Required reviewers         勾選，加自己（不要勾 Prevent self-review）
     Deployment branches        Selected branches and tags → 只加 main
     Environment secret         GCP_PROD_SERVICE_ACCOUNT = $PROD_SA
之後每次合併進 main：deploy 自動跑；deploy-dbt 等你在 Actions 頁面按核准；通過後 deploy-checks 換映像。
EOF
