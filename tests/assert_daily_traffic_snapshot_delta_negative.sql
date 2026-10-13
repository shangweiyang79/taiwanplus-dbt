{{ config(severity='warn') }}

-- IG 2026-06-01 之前的舊算法是快照相減，快照異常時會出現負數（2026-10-13 實測：2026-04-22 Connected 出現負數）。
-- 只警告：那是來源資料的歷史狀況，不影響 6/1 之後的 API 數字。
select date, dept_scope, platform, views
from {{ ref('fct_daily_traffic') }}
where views < 0 and source_method = 'snapshot_delta'
