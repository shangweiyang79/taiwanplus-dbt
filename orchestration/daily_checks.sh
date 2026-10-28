#!/usr/bin/env bash
# 每日資料檢查：Cloud Run Job dbt-daily-checks 的進入點。
#
# marts 都是 view，查詢時才讀原始表，資料本來就是最新的，所以每天不必重建 model。
# 這個 job 只做唯讀檢查，執行身分 dbt-runner 也只有讀取權限：
#   1. source freshness：各平台的 ingestion 是否按時把資料送進來
#   2. test：新進來的資料是否還符合所有 test（對帳、非負、對照表一致……）
# 兩步都會跑完，任一步失敗就以非 0 結束 → Cloud Run 標記執行失敗 → Cloud Monitoring 發信。
set -u

status=0

echo "== 1/2 dbt source freshness =="
dbt source freshness --target prod || status=1

echo "== 2/2 dbt test =="
dbt test --target prod || status=1

if [ "$status" -ne 0 ]; then
  echo "每日檢查失敗：往上找 ERROR / FAIL 看是哪個 source 或 test。"
fi
exit "$status"
