-- 一列 = 一支 YouTube 影片，涵蓋新聞部三個單位。
-- 原本的 social_hub.v_metrics_youtube 讀 video_news_livestream（只有 newsroom），
-- 這裡改讀 video_news_broad；newsroom 部分兩者實測完全一致。
--
-- orientation 靠 stg_youtube__shorts 名單判斷，不能用長度判斷（Shorts 與一般新聞短片的長度分布完全重疊）。
-- 名單每週更新、涵蓋新聞部 4 個頻道（含 Talks / Connected），見 stg_youtube__shorts。
select
  y.video_id                                          as join_key,
  'YouTube'                                           as platform,
  y.dept_scope,
  y.total_views                                       as views,
  -- Engaged views：計算方式接近 2026-08-27 之前的舊 Views，輔助參考用（KPI 仍是 views）
  y.total_engaged_views                               as engaged_views,
  y.total_watch_time_hours                            as watch_time_hours,
  y.total_likes + y.total_comments + y.total_shares   as engagements,
  y.total_impressions                                 as impressions,
  y.total_ctr                                         as ctr,
  y.video_title                                       as platform_title,
  -- 沿用舊 view 的 UTC 日期，維持對帳一致
  date(y.time_published)                              as platform_published_date,
  if(s.video_id is not null, 'shorts', 'video')       as orientation,
  s.video_id is not null                              as is_vertical,
  -- 頻道名稱取自 seed youtube_channels（與每日流量同一份），不用 metadata 的 channel_display_name，
  -- 兩層才不會在頻道改名時對不起來；改名由 assert_youtube_channels_match_video_news_broad 抓。
  c.channel_name,
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
left join {{ ref('stg_youtube__shorts') }} s
  on y.video_id = s.video_id
left join {{ ref('youtube_channels') }} c
  on y.channel_id = c.channel_id
