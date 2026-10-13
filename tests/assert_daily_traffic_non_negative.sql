-- 每日流量的觀看數與觀看時數都不應該是負數。
-- IG 已改成逐支 reel 相減並取累計最大值（stg_daily__instagram_reel_deltas），API 漏抓不會再造成負數；
-- 若這個測試失敗，代表來源出現了新型態的異常，需要檢查。
select date, dept_scope, platform, content_type, views, watch_time_hours, source_method
from {{ ref('fct_daily_traffic') }}
where views < 0 or watch_time_hours < 0
