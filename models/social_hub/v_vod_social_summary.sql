-- 相容 view：一列 = 一支 VOD（只有 Newsroom），給 Looker Studio 的搜尋表格用。
-- 同一支片同一平台可能有多則貼文（例：260719003 有兩則 Facebook），此處為加總。
select
  vod_id,
  publish_date,
  any_value(title)                                              as title,
  any_value(brightcove_id)                                      as brightcove_id,

  -- 分類是 VOD 層屬性，grain 已是 vod_id，值必唯一
  any_value(program)                                            as program,
  any_value(content_category)                                   as content_category,
  any_value(new_category)                                       as new_category,
  any_value(tags_text)                                          as tags_text,

  sum(if(platform = 'YouTube',   views, null))                  as yt_views,
  sum(if(platform = 'Instagram', views, null))                  as ig_views,
  sum(if(platform = 'Facebook',  views, null))                  as fb_views,
  sum(if(platform = 'X',         views, null))                  as x_views,
  sum(views)                                                    as total_views,

  sum(if(platform = 'YouTube',   watch_time_hours, null))       as yt_watch_hours,
  sum(if(platform = 'Instagram', watch_time_hours, null))       as ig_watch_hours,
  sum(if(platform = 'Facebook',  watch_time_hours, null))       as fb_watch_hours,
  sum(watch_time_hours)                                         as total_watch_hours,
  sum(engagements)                                              as total_engagements,

  -- 這支片實際發布到哪些平台，以及其中有幾則拿得到成效
  string_agg(distinct platform order by platform)               as platforms,
  count(*)                                                      as post_count,
  countif(has_metrics)                                          as posts_with_metrics,
  -- orientation 是貼文層屬性，無法收斂成一格，只給「有幾則是直式」
  countif(is_vertical)                                          as vertical_post_count
from {{ ref('v_vod_social_performance') }}
group by vod_id, publish_date
