#!/usr/bin/env bash
# 建立 CI 與每日檢查需要的 GCP 資源。可重複執行：已存在的資源會跳過，IAM binding 本身就是冪等的。
#
# 用法（在 repo 根目錄，帳號需為專案 owner；Git Bash 或 Cloud Shell 皆可）：
#   GCP_PROJECT=<gcp-project> ALERT_EMAIL=<you@example.com> bash orchestration/setup_gcp.sh
#
# 建立的東西：
#   dbt-runner SA   每日檢查 job 的執行身分 + Scheduler 觸發身分。只有讀取權限，不能改 prod。
#   dbt-ci SA       CI 用。可讀全部資料，只能寫 dbt_ci dataset。
#   dbt_ci dataset  CI 建 model 的地方
#   WIF pool/provider  只信任 GITHUB_REPO 這個 repo 發出的 GitHub OIDC token
#   Cloud Run Job dbt-daily-checks + Cloud Scheduler 每日觸發
#   Cloud Monitoring 告警：job 執行失敗就寄信到 ALERT_EMAIL（沒設就跳過）
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GCP_PROJECT:?請設定 GCP_PROJECT}"
REGION=asia-east1
GITHUB_REPO="${GITHUB_REPO:-shangweiyang79/taiwanplus-dbt}"
CI_DATASET="${DBT_CI_DATASET:-dbt_ci}"
JOB=dbt-daily-checks
# 台北時間 12:00：各平台 ingestion 約在 9:30–11:00 跑完
SCHEDULE="${SCHEDULE:-0 12 * * *}"
POOL=github
PROVIDER=github-oidc

# 本機 gcloud 的預設 quota project 不是這個專案，不加 --billing-project 會報 API disabled
P=(--project="$GCP_PROJECT" --billing-project="$GCP_PROJECT")
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" "${P[@]}" --format='value(projectNumber)')
RUNNER_SA="dbt-runner@$GCP_PROJECT.iam.gserviceaccount.com"
CI_SA="dbt-ci@$GCP_PROJECT.iam.gserviceaccount.com"

echo "== API =="
# 這個專案沒開 Service Usage API，所以這一步用預設 quota project 呼叫（不加 --billing-project）
gcloud services enable sts.googleapis.com --project="$GCP_PROJECT"

echo "== Service accounts =="
ensure_sa() {
  gcloud iam service-accounts describe "$1@$GCP_PROJECT.iam.gserviceaccount.com" "${P[@]}" >/dev/null 2>&1 ||
    gcloud iam service-accounts create "$1" --display-name="$2" --description="$3" "${P[@]}"
}
ensure_sa dbt-runner "dbt daily checks" "Cloud Run Job dbt-daily-checks: read-only source freshness + dbt test on prod"
ensure_sa dbt-ci "dbt CI" "GitHub Actions via WIF: dbt build into the CI dataset only"

# readSessionUser：dbt v2（Fusion）用 BigQuery Storage Read API 取回查詢結果，沒有它會報 dbt1308
for sa in "$RUNNER_SA" "$CI_SA"; do
  for role in roles/bigquery.dataViewer roles/bigquery.jobUser roles/bigquery.readSessionUser; do
    gcloud projects add-iam-policy-binding "$GCP_PROJECT" --member="serviceAccount:$sa" --role="$role" \
      --condition=None --quiet "${P[@]}" >/dev/null
  done
done

echo "== CI dataset =="
bq --project_id="$GCP_PROJECT" show "$CI_DATASET" >/dev/null 2>&1 ||
  bq --project_id="$GCP_PROJECT" --location="$REGION" mk --dataset \
    --description="dbt CI（GitHub Actions）建 model 的地方，內容隨時會被覆蓋" "$GCP_PROJECT:$CI_DATASET"
bq --project_id="$GCP_PROJECT" --location="$REGION" query --use_legacy_sql=false --quiet \
  "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$GCP_PROJECT.$CI_DATASET\` TO \"serviceAccount:$CI_SA\"" >/dev/null

echo "== Workload Identity Federation =="
gcloud iam workload-identity-pools describe "$POOL" --location=global "${P[@]}" >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools create "$POOL" --location=global --display-name="GitHub Actions" "${P[@]}"
gcloud iam workload-identity-pools providers describe "$PROVIDER" --workload-identity-pool="$POOL" \
  --location=global "${P[@]}" >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" --workload-identity-pool="$POOL" \
    --location=global --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository == '$GITHUB_REPO'" "${P[@]}"
gcloud iam service-accounts add-iam-policy-binding "$CI_SA" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/attribute.repository/$GITHUB_REPO" \
  "${P[@]}" >/dev/null

echo "== Cloud Run Job（Cloud Build 用根目錄的 Dockerfile 建映像）=="
# 重跑 test 不會改變結果，所以不重試
gcloud run jobs deploy "$JOB" --source=. --region="$REGION" \
  --service-account="$RUNNER_SA" --set-env-vars="GCP_PROJECT=$GCP_PROJECT" \
  --max-retries=0 --task-timeout=30m --memory=1Gi --cpu=1 "${P[@]}"

echo "== Cloud Scheduler =="
gcloud run jobs add-iam-policy-binding "$JOB" --region="$REGION" \
  --member="serviceAccount:$RUNNER_SA" --role=roles/run.invoker "${P[@]}" >/dev/null
gcloud scheduler jobs describe "$JOB-trigger" --location="$REGION" "${P[@]}" >/dev/null 2>&1 ||
  gcloud scheduler jobs create http "$JOB-trigger" --location="$REGION" \
    --schedule="$SCHEDULE" --time-zone=Asia/Taipei --http-method=POST \
    --uri="https://$REGION-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/$GCP_PROJECT/jobs/$JOB:run" \
    --oauth-service-account-email="$RUNNER_SA" "${P[@]}"

if [ -n "${ALERT_EMAIL:-}" ]; then
  echo "== 告警 =="
  CH=$(gcloud beta monitoring channels list --filter="type=\"email\" AND labels.email_address=\"$ALERT_EMAIL\"" \
    --format='value(name)' "${P[@]}" | head -n1)
  if [ -z "$CH" ]; then
    CH=$(gcloud beta monitoring channels create --type=email --display-name="dbt alerts" \
      --channel-labels="email_address=$ALERT_EMAIL" --format='value(name)' "${P[@]}")
  fi
  if [ -z "$(gcloud alpha monitoring policies list --filter='displayName="dbt-daily-checks failed"' \
    --format='value(name)' "${P[@]}")" ]; then
    gcloud alpha monitoring policies create --policy-from-file=orchestration/alert_policy.json \
      --notification-channels="$CH" "${P[@]}"
  fi
else
  echo "== 告警：沒設 ALERT_EMAIL，跳過 =="
fi

cat <<EOF

完成。到 GitHub repo → Settings → Secrets and variables → Actions 新增 3 個 repository secret：
  GCP_PROJECT              $GCP_PROJECT
  GCP_WIF_PROVIDER         projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER
  GCP_CI_SERVICE_ACCOUNT   $CI_SA
手動跑一次每日檢查：gcloud run jobs execute $JOB --region=$REGION ${P[*]}
EOF
