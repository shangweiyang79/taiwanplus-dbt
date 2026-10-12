-- 一列 = 一則 CMS 記錄的社群貼文（VOD × 平台），只涵蓋 Newsroom。
-- metrics_key：IG 的 join_key 存的是完整 link，要抽出 shortcode 才對得上 stg_instagram__reels；
-- 其他平台 regexp_extract 回 NULL，退回原本的 join_key。
select
  vod_id,
  publish_date,
  title,
  brightcove_id,
  platform,
  post_id,
  link,
  join_key,
  coalesce(regexp_extract(join_key, r'/reel/([^/?]+)'), join_key) as metrics_key,
  ingested_at
from {{ source('social_hub', 'post_map') }}
