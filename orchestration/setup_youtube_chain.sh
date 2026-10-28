#!/usr/bin/env bash
# 建立 YouTube owner 事件驅動鏈（見 youtube_owner_chain.yaml）。可重複執行。
# 前提：已跑過 setup_gcp.sh（dbt-daily-checks job 與告警信箱的 notification channel 已存在），
#       且 Workflows API 已啟用。
#
# 用法（在 repo 根目錄，帳號需為專案 owner）：
#   GCP_PROJECT=<gcp-project> ALERT_EMAIL=<you@example.com> bash orchestration/setup_youtube_chain.sh
#
# 這個腳本不會停用舊的 BQ 排程查詢；驗證新鏈的結果正確後再手動停用，步驟見 orchestration/README.md。
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GCP_PROJECT:?請設定 GCP_PROJECT}"
REGION=asia-east1
WORKFLOW=youtube-owner-chain
TOPIC=youtube-owner-transfer-runs
TRIGGER=youtube-owner-transfer-finished
JOB=dbt-daily-checks

P=(--project="$GCP_PROJECT" --billing-project="$GCP_PROJECT")
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" "${P[@]}" --format='value(projectNumber)')
SA="yt-chain@$GCP_PROJECT.iam.gserviceaccount.com"
DTS_AGENT="service-$PROJECT_NUMBER@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
bq_sql() { bq --project_id="$GCP_PROJECT" --location="$REGION" query --use_legacy_sql=false --quiet "$@" >/dev/null; }

echo "== Service account =="
gcloud iam service-accounts describe "$SA" "${P[@]}" >/dev/null 2>&1 ||
  gcloud iam service-accounts create yt-chain --display-name="YouTube owner chain" \
    --description="Workflow youtube-owner-chain: refresh YouTube summary tables, then run dbt checks" "${P[@]}"
# run.viewer：Cloud Run connector 要用 run.operations.get 等 job 執行結束
for role in roles/bigquery.jobUser roles/logging.logWriter roles/workflows.invoker roles/eventarc.eventReceiver roles/run.viewer; do
  gcloud projects add-iam-policy-binding "$GCP_PROJECT" --member="serviceAccount:$SA" --role="$role" \
    --condition=None --quiet "${P[@]}" >/dev/null
done
# 只讀 owner 報表、只寫 YouTube 彙總 dataset
bq_sql "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$GCP_PROJECT.youtube_taiwanplus_owner\` TO \"serviceAccount:$SA\""
bq_sql "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$GCP_PROJECT.youtube_channel_summary\` TO \"serviceAccount:$SA\""
gcloud run jobs add-iam-policy-binding "$JOB" --region="$REGION" \
  --member="serviceAccount:$SA" --role=roles/run.invoker "${P[@]}" >/dev/null

echo "== Stored procedures =="
for f in orchestration/sql/*.sql; do
  bq_sql < "$f"
  echo "  $(basename "$f" .sql)"
done

echo "== Pub/Sub：owner transfer 每次執行結束都發通知 =="
gcloud pubsub topics describe "$TOPIC" "${P[@]}" >/dev/null 2>&1 || gcloud pubsub topics create "$TOPIC" "${P[@]}"
gcloud pubsub topics add-iam-policy-binding "$TOPIC" --member="serviceAccount:$DTS_AGENT" \
  --role=roles/pubsub.publisher "${P[@]}" >/dev/null
TOKEN=$(gcloud auth print-access-token)
API=https://bigquerydatatransfer.googleapis.com/v1
CONFIG=$(curl -sf -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $GCP_PROJECT" \
    "$API/projects/$GCP_PROJECT/locations/$REGION/transferConfigs?dataSourceIds=youtube_content_owner" |
  python -c "import sys,json; c=json.load(sys.stdin)['transferConfigs']; assert len(c)==1, c; print(c[0]['name'])")
curl -sf -X PATCH -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $GCP_PROJECT" \
  -H "Content-Type: application/json" \
  -d "{\"notificationPubsubTopic\": \"projects/$GCP_PROJECT/topics/$TOPIC\"}" \
  "$API/$CONFIG?updateMask=notification_pubsub_topic" >/dev/null
echo "  $CONFIG → $TOPIC"

echo "== Workflow =="
gcloud workflows deploy "$WORKFLOW" --source=orchestration/youtube_owner_chain.yaml \
  --location="$REGION" --service-account="$SA" "${P[@]}"

echo "== Eventarc：Pub/Sub 通知 → workflow =="
gcloud eventarc triggers describe "$TRIGGER" --location="$REGION" "${P[@]}" >/dev/null 2>&1 ||
  gcloud eventarc triggers create "$TRIGGER" --location="$REGION" \
    --destination-workflow="$WORKFLOW" --destination-workflow-location="$REGION" \
    --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished" \
    --transport-topic="projects/$GCP_PROJECT/topics/$TOPIC" \
    --service-account="$SA" "${P[@]}"

if [ -n "${ALERT_EMAIL:-}" ]; then
  echo "== 告警 =="
  CH=$(gcloud beta monitoring channels list --filter="type=\"email\" AND labels.email_address=\"$ALERT_EMAIL\"" \
    --format='value(name)' "${P[@]}" | head -n1)
  : "${CH:?找不到 $ALERT_EMAIL 的 notification channel，先跑 setup_gcp.sh}"
  if [ -z "$(gcloud alpha monitoring policies list --filter='displayName="youtube-owner-chain failed"' \
    --format='value(name)' "${P[@]}")" ]; then
    gcloud alpha monitoring policies create --policy-from-file=orchestration/workflow_alert_policy.json \
      --notification-channels="$CH" "${P[@]}"
  fi
fi

cat <<EOF

完成。手動跑一次驗證：
  gcloud workflows run $WORKFLOW --location=$REGION --data='{}' ${P[*]}
EOF
