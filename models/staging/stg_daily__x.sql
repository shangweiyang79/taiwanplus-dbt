-- 一列 = 日，Newsroom X 帳號的每日流量（X 後台每日流量匯出）。
select
  date,
  'newsroom'                                        as dept_scope,
  'X'                                               as platform,
  'video'                                           as content_type,
  views,
  cast(null as int64)                               as paid_views,
  cast(null as int64)                               as engaged_views,
  watch_time_hours,
  'x_analytics'                                     as source_method
from {{ source('x', 'daily_traffic') }}
