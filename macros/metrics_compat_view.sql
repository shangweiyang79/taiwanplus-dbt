{#
  舊 social_hub.v_metrics_<平台> 的相容輸出：欄位與順序和舊 view 完全一致，只取 Newsroom。
  舊 view 的欄位順序是下游 UNION ALL SELECT * 的前提，不能改。
#}
{% macro metrics_compat_view(staging_model) %}
select
  join_key,
  platform,
  views,
  watch_time_hours,
  engagements,
  impressions,
  ctr,
  platform_title,
  platform_published_date,
  orientation,
  is_vertical,
  link,
  caption,
  thumbnail_url
from {{ ref(staging_model) }}
where dept_scope = 'newsroom'
{% endmacro %}
