-- daily_detailed_summary 必須跟上 owner 報表：分辨「YouTube 晚送」和「我們自己的鏈斷了」。
--
-- source freshness 只看衍生表的 MAX(date)，YouTube 晚送（會自己恢復）和
-- Eventarc 沒觸發 / procedure 壞掉（要人處理）看起來一樣。這個測試只看我們這一段：
-- owner 來源表（refresh_daily_detailed_summary 讀的 traffic_source_a3）已經有的報表日，
-- 衍生表就應該也有。YouTube 送得再慢，這個測試都不會失敗。
--
-- 只算 3 小時前就寫入的 partition：transfer 剛寫入時 workflow 還在跑，避免 12:00 的檢查撞到而誤報。
-- 失敗時處理：gcloud workflows run youtube-owner-chain --location=asia-east1 --data='{"force": true}'
-- （procedure MERGE 最近 14 天，兩週內補跑都不會缺資料）。
with owner as (
  select max(partition_id) as owner_max_date
  from `{{ target.database }}.youtube_taiwanplus_owner.INFORMATION_SCHEMA.PARTITIONS`
  where table_name = 'p_content_owner_traffic_source_a3_owner'
    and regexp_contains(partition_id, r'^\d{8}$')
    and total_rows > 0
    and last_modified_time < timestamp_sub(current_timestamp(), interval 3 hour)
),

summary as (
  select max(date) as summary_max_date
  from {{ source('youtube', 'daily_detailed_summary') }}
)

select owner_max_date, summary_max_date
from owner cross join summary
where owner_max_date > summary_max_date
