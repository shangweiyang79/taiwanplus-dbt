-- 一列 = 一支 FB 影片（只有 Newsroom 有 FB），數字為累計值，不需要取快照。
-- views 用 video_views_3s（播放滿 3 秒），是四個平台中門檻最嚴格的。
-- FB 數字大是因為受眾以菲律賓為主、菲律賓相關新聞表現特別好，不是門檻低。跨平台加總只能看量級。
--
-- 資料分兩段：
--   current：TaiwanPlus_news_videos，2026-01-01 起，Cloud Run 每天回刷。
--   history：TaiwanPlus_news_videos_history，2024–2025，2026-11-02 匯出的凍結快照，不再更新。
-- 兩張表照理不重疊（assert_fb_history_no_overlap 會警告）；萬一重疊，以每天更新的 current 為準。
with current_videos as (
  select
    video_id, video_views_3s, hours_viewed, engagements, title, publish_date,
    orientation, permalink, description, thumbnail_url
  from {{ source('facebook', 'TaiwanPlus_news_videos') }}
),

history_videos as (
  select
    h.video_id, h.video_views_3s, h.hours_viewed, h.engagements, h.title, h.publish_date,
    h.orientation, h.permalink, h.description, h.thumbnail_url
  from {{ source('facebook', 'TaiwanPlus_news_videos_history') }} h
  where not exists (select 1 from current_videos c where c.video_id = h.video_id)
),

videos as (
  select * from current_videos
  union all
  select * from history_videos
)

select
  video_id                                        as join_key,
  'Facebook'                                      as platform,
  'newsroom'                                      as dept_scope,
  video_views_3s                                  as views,
  cast(null as int64)                             as engaged_views,
  hours_viewed                                    as watch_time_hours,
  engagements,
  cast(null as int64)                             as impressions,
  cast(null as float64)                           as ctr,
  title                                           as platform_title,
  publish_date                                    as platform_published_date,
  -- 原表值為 'video' / 'reels'
  orientation,
  orientation = 'reels'                           as is_vertical,
  -- reels 的 permalink 是 /reel/{id}/、一般影片是 /watch/?v={id}，直接沿用
  permalink                                       as link,
  description                                     as caption,
  -- Meta CDN 的簽章網址，會過期
  thumbnail_url,
  cast(null as string)                            as channel_name   -- 只有 YouTube 分頻道
from videos
