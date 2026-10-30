#!/usr/bin/env bash
# 建立 CD（合併進 main 後自動部署）需要的 GCP 資源。可重複執行。
# 前提：已跑過 setup_gcp.sh 與 setup_youtube_chain.sh（WIF pool、dbt-daily-checks、youtube-owner-chain 都已存在）。
#
# 用法（在 repo 根目錄，帳號需為專案 owner）：
#   GCP_PROJECT=<gcp-project> bash orchestration/setup_cd.sh
#
# 建立的東西：
#   dbt-deployer SA  GitHub Actions 的 deploy job 用。只能做這三件部署：
#     1. 推 dbt-daily-checks 映像、更新 job 用的映像
#     2. 部署 workflow youtube-owner-chain
#     3. 重建 youtube_channel_summary 裡的 refresh_* stored procedure
#   不能動 dbt 的 prod dataset（dbt build --target prod 仍是手動，之後加人工核准再交給 CD）。
#
# WIF 只讓 main 分支的 workflow 換成這個 SA：PR、其他分支、fork 都拿不到部署權限。
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GCP_PROJECT:?請設定 GCP_PROJECT}"
REGION=asia-east1
GITHUB_REPO="${GITHUB_REPO:-shangweiyang79/taiwanplus-dbt}"
POOL=github
JOB=dbt-daily-checks
AR_REPO=cloud-run-source-deploy   # gcloud run deploy --source 自動建的 repo，現有映像也在這裡

P=(--project="$GCP_PROJECT" --billing-project="$GCP_PROJECT")
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" "${P[@]}" --format='value(projectNumber)')
DEPLOY_SA="dbt-deployer@$GCP_PROJECT.iam.gserviceaccount.com"
RUNNER_SA="dbt-runner@$GCP_PROJECT.iam.gserviceaccount.com"
CHAIN_SA="yt-chain@$GCP_PROJECT.iam.gserviceaccount.com"

echo "== Service account =="
gcloud iam service-accounts describe "$DEPLOY_SA" "${P[@]}" >/dev/null 2>&1 ||
  gcloud iam service-accounts create dbt-deployer --display-name="dbt deployer" \
    --description="GitHub Actions deploy job (main only): daily-checks image, owner-chain workflow, refresh procedures" "${P[@]}"

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
bq --project_id="$GCP_PROJECT" --location="$REGION" query --use_legacy_sql=false --quiet \
  "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$GCP_PROJECT.youtube_channel_summary\` TO \"serviceAccount:$DEPLOY_SA\"" >/dev/null

echo "== WIF：只信任 main 分支 =="
# provider 已把 google.subject 對應到 OIDC 的 sub；push 到 main 的 sub 是 repo:<repo>:ref:refs/heads/main
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" --role=roles/iam.workloadIdentityUser \
  --member="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/subject/repo:$GITHUB_REPO:ref:refs/heads/main" \
  "${P[@]}" >/dev/null

cat <<EOF

完成。到 GitHub repo → Settings → Secrets and variables → Actions 新增 1 個 repository secret：
  GCP_DEPLOY_SERVICE_ACCOUNT   $DEPLOY_SA
之後每次合併進 main，CI 綠燈後 deploy job 會自動部署。也可以在 Actions 頁面對 main 手動執行 CI。
EOF
