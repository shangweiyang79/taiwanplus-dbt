-- 一列 = 一支 FB 影片（只有 Newsroom 有 FB），數字為累計值，不需要取快照。
-- views 用 video_views_3s（播放滿 3 秒），門檻比其他平台低，跨平台加總只能看量級。
select
  video_id                                        as join_key,
  'Facebook'                                      as platform,
  'newsroom'                                      as dept_scope,
  video_views_3s                                  as views,
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
  thumbnail_url
from {{ source('facebook', 'TaiwanPlus_news_videos') }}
