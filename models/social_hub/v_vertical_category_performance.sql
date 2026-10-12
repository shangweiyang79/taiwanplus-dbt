-- 相容 view：一列 = 一則直式貼文（只有 Newsroom），回答「直式影音在各平台哪種主題表現較好」。
--
-- 走 vertical_crosswalk：三個平台放的是同一支影片，IG / FB reel 可以對回 YouTube Short，
-- 繼承 yt_shorts 的主題分類，不需要 vod_id。
--
-- 必讀：
--   1. 這是推論出來的關聯，不是 CMS 的實測記錄。只想要實測記錄時加 WHERE is_confirmed。
--   2. 母體是「有成效數字的 YouTube Shorts」（2026-01 起）。
--   3. 日期一律用 YouTube Short 的發布日（台北時間），不是各平台自己的貼文時間，
--      否則同一支影片會因為跨平台差幾小時而落在不同月份。
--   4. X 不在這裡：沒有直式 / 橫式資訊。
--   5. 各平台「觀看」定義不同，跨平台比 views 只能當粗略量級看。
with metrics as (
  select join_key, platform, views, watch_time_hours, engagements
  from {{ ref('int_platform_metrics_unioned') }}
  where dept_scope = 'newsroom'
    and platform in ('YouTube', 'Instagram', 'Facebook')
)
select
  x.platform,
  x.post_id,
  x.yt_video_id,
  -- post_map 有記錄才有；正因為多數直式貼文沒有，才需要這張 crosswalk
  x.vod_id,

  date(y.time_published, 'Asia/Taipei')                   as video_publish_date,
  x.publish_time                                          as post_published_time,

  s.title                                                 as video_title,
  s.new_category,
  -- tags 是 ARRAY，刻意不帶進長表（Looker Studio 會爆掉），要做 tag 分析請查 yt_shorts.tags
  s.tags_text,
  -- NULL = 尚未判定，不是「不是 bite reel」，比較時母體要用 IS NOT NULL
  s.bite_reel,

  m.views,
  m.watch_time_hours,
  m.engagements,

  x.match_method,
  x.match_residual,
  -- 'self' 是 YouTube 自己、'post_map' 是 CMS 實測記錄，其餘為推論
  x.match_method in ('self', 'post_map')                  as is_confirmed,
  m.join_key is not null                                  as has_metrics
from {{ source('social_hub', 'vertical_crosswalk') }} x
join {{ source('social_hub', 'yt_shorts') }} s
  on s.video_id = x.yt_video_id
join {{ ref('stg_youtube__videos') }} y
  on y.join_key = x.yt_video_id
  and y.dept_scope = 'newsroom'
left join metrics m
  on m.platform = x.platform and m.join_key = x.post_id
