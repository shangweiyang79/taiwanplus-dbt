-- 一列 = 日 × 新聞部單位，IG 影片類 Stories 的觀看（來源 view 已篩 media_type = 'VIDEO'）。
-- 數字是該日發布的 Stories 的累計觀看；Stories 只存在 24 小時，所以近似當天流量。
-- Social（Program）不屬於新聞部，不取。

{%- set accounts = [('News', 'newsroom'), ('Talks', 'talks'), ('Connected', 'connected')] %}

{% for col, scope in accounts %}
select
  date,
  '{{ scope }}'                                     as dept_scope,
  'Instagram'                                       as platform,
  'story'                                           as content_type,
  `IG {{ col }} Story VV`                           as views,
  cast(null as int64)                               as paid_views,
  cast(null as int64)                               as engaged_views,
  cast(null as float64)                             as watch_time_hours,
  'story_by_publish_date'                           as source_method
from {{ source('instagram', 'ig_stories_pivot_daily') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
