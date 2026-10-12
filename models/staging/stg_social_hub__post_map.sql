-- 一列 = 一則 CMS 記錄的社群貼文（VOD × 平台），只涵蓋 Newsroom。
-- metrics_key：IG 的 join_key 存的是完整 link，要抽出 shortcode 才對得上 stg_instagram__reels；
-- 其他平台 regexp_extract 回 NULL，退回原本的 join_key。
-- CMS 有少數 IG 記錄的 join_key 是空字串（2026-10-12 實測 4 支 VOD），轉成 NULL，
-- 否則它們會被當成「同一則貼文」。這些記錄本來就對不到成效，不影響數字。
select
  vod_id,
  publish_date,
  title,
  brightcove_id,
  platform,
  post_id,
  link,
  join_key,
  nullif(coalesce(regexp_extract(join_key, r'/reel/([^/?]+)'), join_key), '') as metrics_key,
  ingested_at
from {{ source('social_hub', 'post_map') }}
