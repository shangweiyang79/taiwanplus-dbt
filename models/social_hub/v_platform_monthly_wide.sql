-- 相容 view：一列 = 一個月，四平台攤平成欄位。Looker Studio 四平台儀表板直接接這張。
-- 母體與舊 view 相同（只有 Newsroom）。
-- total_views 是四個定義不同的「觀看」硬加起來，只能看趨勢，不能比較平台優劣。
-- X 沒有觀看時長，所以沒有 x_watch_hours。
select
  year_month,
  month_start,

  sum(if(platform = 'YouTube',   views, null))            as yt_views,
  sum(if(platform = 'Instagram', views, null))            as ig_views,
  sum(if(platform = 'Facebook',  views, null))            as fb_views,
  sum(if(platform = 'X',         views, null))            as x_views,
  sum(views)                                              as total_views,

  sum(if(platform = 'YouTube',   watch_time_hours, null)) as yt_watch_hours,
  sum(if(platform = 'Instagram', watch_time_hours, null)) as ig_watch_hours,
  sum(if(platform = 'Facebook',  watch_time_hours, null)) as fb_watch_hours,
  sum(watch_time_hours)                                   as total_watch_hours,

  sum(if(platform = 'YouTube',   engagements, null))      as yt_engagements,
  sum(if(platform = 'Instagram', engagements, null))      as ig_engagements,
  sum(if(platform = 'Facebook',  engagements, null))      as fb_engagements,
  sum(if(platform = 'X',         engagements, null))      as x_engagements,
  sum(engagements)                                        as total_engagements,

  countif(platform = 'YouTube')                           as yt_post_count,
  countif(platform = 'Instagram')                         as ig_post_count,
  countif(platform = 'Facebook')                          as fb_post_count,
  countif(platform = 'X')                                 as x_post_count,
  count(*)                                                as total_post_count,
  countif(is_in_post_map)                                 as posts_in_post_map
from {{ ref('v_platform_post_performance') }}
group by year_month, month_start
