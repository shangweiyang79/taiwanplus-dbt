-- 一列 = 一則 X 貼文（只有 Newsroom 有 X），數字為最新值。
select
  post_id                                         as join_key,
  'X'                                             as platform,
  'newsroom'                                      as dept_scope,
  total_video_views                               as views,
  cast(null as int64)                             as engaged_views,
  -- X 不提供觀看時長
  cast(null as float64)                           as watch_time_hours,
  -- 不用 total_actions（= likes + shares，不含留言，會低估約 5%），
  -- 自行加總三項，與 YouTube / Facebook 的互動定義一致
  likes + comments_replies + shares_retweets      as engagements,
  cast(null as int64)                             as impressions,
  cast(null as float64)                           as ctr,
  content                                         as platform_title,
  publish_date                                    as platform_published_date,
  -- X 沒有直式 / 橫式資訊：'video' / FALSE 代表「無此區分」，比較直式成效時應排除 X
  'video'                                         as orientation,
  false                                           as is_vertical,
  link,
  content                                         as caption,
  -- 由 x_thumbnails_bq.py 抓回，不會過期
  thumbnail_url
from {{ source('x', 'post_metrics') }}
