-- 相容 view：與舊 social_hub.v_platform_post_performance 欄位、母體完全相同（只有 Newsroom）。
-- Looker Studio 接的是這個名稱。新分析請用 fct_social_post_performance（新聞部三個單位）。
select
  platform,
  post_key,
  link,
  publish_date,
  year_month,
  month_start,
  platform_title,
  caption,
  thumbnail_url,
  views,
  watch_time_hours,
  engagements,
  impressions,
  ctr,
  orientation,
  is_vertical,
  vod_id,
  is_in_post_map,
  program,
  content_category,
  new_category,
  tags_text
from {{ ref('fct_social_post_performance') }}
where dept_scope = 'newsroom'
