-- 一列 = 日，Newsroom FB 粉專的每日流量。
-- page_video_views 是 3 秒觀看，含付費（page_video_views_paid 另列）。
-- page_video_view_time 實測推斷單位為分鐘（2026-09 平均每次約 25 秒，總時數與影片層同量級），換算成小時。
select
  date,
  'newsroom'                                        as dept_scope,
  'Facebook'                                        as platform,
  'video'                                           as content_type,
  page_video_views                                  as views,
  page_video_views_paid                             as paid_views,
  cast(null as int64)                               as engaged_views,
  page_video_view_time / 60                         as watch_time_hours,
  'facebook_insights'                               as source_method
from {{ source('facebook', 'TaiwanPlus_news') }}
