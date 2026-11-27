-- daily_detailed_summary 必須跟上 owner 報表：分辨「YouTube 晚送」和「我們自己的鏈斷了」。
--
-- source freshness 只看衍生表的 MAX(date)，YouTube 晚送（會自己恢復）和
-- Eventarc 沒觸發 / procedure 壞掉（要人處理）看起來一樣。這個測試只看我們這一段：
-- owner 來源表（refresh_daily_detailed_summary 讀的 traffic_source_a3）已經有的報表日，
-- 衍生表就應該也有。YouTube 送得再慢，這個測試都不會失敗。
--
-- 逐日比對、不是只比 MAX：YouTube 會亂序送（2026-11-27 的 11/23 比 11/24 晚一天才到），
-- 只比 MAX 會漏掉中間缺的那天。範圍是近 14 天，和 procedure 的 MERGE 視窗一樣
-- （更早缺的日子 procedure 也補不回來，要另外處理）。workflow 判斷要不要重建用的是同一個規則。
--
-- 只算 3 小時前就寫入的 partition：transfer 剛寫入時 workflow 還在跑，避免 12:00 的檢查撞到而誤報。
-- 失敗時處理：gcloud workflows run youtube-owner-chain --location=asia-east1 --data='{"force": true}'
-- （procedure MERGE 最近 14 天，兩週內補跑都不會缺資料）。
with owner as (
  select partition_id as report_date
  from `{{ target.database }}.youtube_taiwanplus_owner.INFORMATION_SCHEMA.PARTITIONS`
  where table_name = 'p_content_owner_traffic_source_a3_owner'
    and regexp_contains(partition_id, r'^\d{8}$')
    and partition_id >= format_date('%Y%m%d', date_sub(current_date(), interval 14 day))
    and total_rows > 0
    and last_modified_time < timestamp_sub(current_timestamp(), interval 3 hour)
),

summary as (
  select distinct date as report_date
  from {{ source('youtube', 'daily_detailed_summary') }}
  where date >= format_date('%Y%m%d', date_sub(current_date(), interval 14 day))
)

select owner.report_date as missing_in_summary
from owner
left join summary using (report_date)
where summary.report_date is null
