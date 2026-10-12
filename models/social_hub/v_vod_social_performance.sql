-- 相容 view：一列 = 一則有 VOD ID 的貼文（post_map 為骨幹，只有 Newsroom）。
-- 與舊 social_hub.v_vod_social_performance 欄位、母體完全相同。
--
-- 只 join Newsroom 的成效：舊 view 的成效來源只有 Newsroom 帳號，
-- 若 post_map 裡有其他單位的貼文，舊 view 會顯示 has_metrics = false，這裡維持一致。
with metrics as (
  select *
  from {{ ref('int_platform_metrics_unioned') }}
  where dept_scope = 'newsroom'
)
select
  p.vod_id,
  p.publish_date,
  p.title,
  p.brightcove_id,
  p.platform,
  p.post_id,
  p.link,
  m.views,
  m.watch_time_hours,
  m.engagements,
  m.impressions,
  m.ctr,
  m.platform_published_date,
  m.orientation,
  m.is_vertical,
  m.platform_title,
  m.caption,
  m.thumbnail_url,
  -- 母體不含 newscasts 與 Shorts，約兩成貼文這幾欄是 NULL，屬預期行為
  c.program,
  c.content_category,
  c.new_category,
  -- tags 是 ARRAY，刻意不帶進長表（Looker Studio 會爆掉）
  c.tags_text,
  m.join_key is not null as has_metrics
from {{ ref('stg_social_hub__post_map') }} p
left join metrics m
  on  p.metrics_key = m.join_key
  and p.platform = m.platform
left join {{ ref('vod_category') }} c
  on p.vod_id = c.vod_id
