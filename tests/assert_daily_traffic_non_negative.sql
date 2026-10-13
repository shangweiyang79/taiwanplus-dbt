-- 每日流量不應該是負數。IG 舊算法（snapshot_delta，快照相減）偶有負數，另由 warn 等級的測試追蹤，這裡排除。
select date, dept_scope, platform, content_type, views, source_method
from {{ ref('fct_daily_traffic') }}
where views < 0 and source_method != 'snapshot_delta'
