#!/usr/bin/env bash
# 停用／恢復被 youtube-owner-chain 取代的三個 BQ 排程查詢（只切換 disabled，不刪除）。
#   GCP_PROJECT=<gcp-project> bash orchestration/toggle_old_schedules.sh disable   # 新鏈驗證通過後
#   GCP_PROJECT=<gcp-project> bash orchestration/toggle_old_schedules.sh enable    # 回滾
set -euo pipefail

: "${GCP_PROJECT:?請設定 GCP_PROJECT}"
case "${1:-}" in
  disable) DISABLED=true ;;
  enable)  DISABLED=false ;;
  *) echo "用法：$0 disable|enable" >&2; exit 2 ;;
esac
NAMES="daily_youtube_sum_update yt_video_news_livestream yt_video_news_broad"

TOKEN=$(gcloud auth print-access-token)
API=https://bigquerydatatransfer.googleapis.com/v1
H=(-H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $GCP_PROJECT")

curl -sf "${H[@]}" "$API/projects/$GCP_PROJECT/locations/asia-east1/transferConfigs?dataSourceIds=scheduled_query&pageSize=100" |
  python -c "
import sys, json
want = set('$NAMES'.split())
for c in json.load(sys.stdin).get('transferConfigs', []):
    if c['displayName'] in want:
        print(c['name'], c['displayName'])
" | tr -d '\r' | while read -r name display; do  # Windows 的 Python 輸出 CRLF
  curl -sf -X PATCH "${H[@]}" -H "Content-Type: application/json" -d "{\"disabled\": $DISABLED}" \
    "$API/$name?updateMask=disabled" >/dev/null
  echo "$display → disabled=$DISABLED"
done
