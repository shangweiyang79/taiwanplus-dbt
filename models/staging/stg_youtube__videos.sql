-- 一列 = 一支 YouTube 影片，涵蓋新聞部三個單位。
-- 原本的 social_hub.v_metrics_youtube 讀 video_news_livestream（只有 newsroom），
-- 這裡改讀 video_news_broad；newsroom 部分兩者實測完全一致。
--
-- orientation 靠 yt_shorts 清單判斷，不能用長度判斷（Shorts 與一般新聞短片的長度分布完全重疊）。
-- yt_shorts 目前只涵蓋 TaiwanPlus News / Taiwan Explained，Talks / Connected 的 Shorts 會被當成 'video'。
select
  y.video_id                                          as join_key,
  'YouTube'                                           as platform,
  y.dept_scope,
  y.total_views                                       as views,
  y.total_watch_time_hours                            as watch_time_hours,
  y.total_likes + y.total_comments + y.total_shares   as engagements,
  y.total_impressions                                 as impressions,
  y.total_ctr                                         as ctr,
  y.video_title                                       as platform_title,
  -- 沿用舊 view 的 UTC 日期，維持對帳一致
  date(y.time_published)                              as platform_published_date,
  if(s.video_id is not null, 'shorts', 'video')       as orientation,
  s.video_id is not null                              as is_vertical,
  y.video_url                                         as link,
  cast(null as string)                                as caption,
  -- 唯一自己組出來的網址：YouTube 穩定公開、不會過期的縮圖格式
  concat('https://i.ytimg.com/vi/', y.video_id, '/hqdefault.jpg') as thumbnail_url,
  -- 以下為 YouTube 專屬欄位，不進跨平台 union
  y.channel_id,
  y.channel_display_name,
  y.video_length,
  y.time_published
from {{ source('youtube', 'video_news_broad') }} y
left join {{ source('social_hub', 'yt_shorts') }} s
  on y.video_id = s.video_id
