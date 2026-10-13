-- 一列 = 新聞部（Newsroom + Talks + Connected）在任一平台上的一則影片貼文。
-- 新聞部社群成效的主表，semantic layer 建在這裡。
--
-- 不經過 post_map：直接取各平台原表的所有影片，包含沒走 CMS 的貼文、newscasts、直播。
-- post_map 只當附加維度，best-effort 補上 vod_id 與主題分類，對不到就是 NULL。
-- post_map / vod_category 只涵蓋 Newsroom，所以 Talks / Connected 的 vod_id、分類欄位一律為 NULL。
--
-- 必讀：
--   1. 各平台「觀看」門檻與受眾都不同，跨平台加總只能看量級，不能比較平台優劣。
--      YouTube 的 Views 於 2026-08-27 放寬（30 秒 → 1 秒），跨 8/27 比較時另附 engaged_views 參考（KPI 仍是 views）。
--   2. 數字都是累計值，愈晚發布累計愈少，最新月份天生偏低。
--   3. impressions / ctr 只有 YouTube 有；watch_time_hours X 沒有。
select
  -- 單欄唯一鍵（semantic layer 的 primary entity）：不同平台的貼文 ID 理論上可能撞號
  concat(m.platform, ':', m.join_key)               as post_uid,
  m.platform,
  m.dept_scope,
  m.join_key                                        as post_key,
  m.link,
  -- 各平台自己的發布日，不是 VOD 的 publish_date
  m.platform_published_date                         as publish_date,
  format_date('%Y-%m', m.platform_published_date)   as year_month,
  date_trunc(m.platform_published_date, month)      as month_start,
  m.platform_title,
  m.caption,
  m.thumbnail_url,

  m.views,
  m.engaged_views,
  m.watch_time_hours,
  m.engagements,
  m.impressions,
  m.ctr,
  m.orientation,
  m.is_vertical,

  pm.vod_id,
  pm.vod_id is not null                             as is_in_post_map,
  c.program,
  c.content_category,
  c.new_category,
  c.tags_text
from {{ ref('int_platform_metrics_unioned') }} m
left join {{ ref('int_post_map_dedup') }} pm
  on m.platform = pm.platform and m.join_key = pm.metrics_key
left join {{ ref('vod_category') }} c
  on pm.vod_id = c.vod_id
where m.platform_published_date is not null
