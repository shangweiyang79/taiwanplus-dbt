-- 一列 = 一則平台貼文 / 一支影片，四個平台、新聞部三個單位疊在一起。
-- 欄位明確列出，不用 SELECT *，避免任何一個 staging 欄位順序改變時 union 靜默錯位。

{%- set cols = [
    'join_key', 'platform', 'dept_scope',
    'views', 'watch_time_hours', 'engagements', 'impressions', 'ctr',
    'platform_title', 'platform_published_date', 'orientation', 'is_vertical',
    'link', 'caption', 'thumbnail_url',
] %}

{%- set models = [
    'stg_youtube__videos',
    'stg_instagram__reels',
    'stg_x__posts',
    'stg_facebook__videos',
] %}

{% for m in models %}
select {{ cols | join(', ') }}
from {{ ref(m) }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
