-- 一列 = 一支 IG reel，涵蓋新聞部三個 IG 帳號。
--
-- 原表是每日累計快照，必須取最新 data_date 那一列；直接 SUM 會灌水上百倍
-- （實測 News 2026-03：直接 SUM 約為正確值的 107 倍）。
-- join key 用 URL 裡的 shortcode：Post ID 是媒體 ID，與 shortcode 無關；比對整串 link 會被結尾斜線 / query string 弄壞。
-- 三個帳號的 link 實測 100% 是 /reel/。
-- Talks / Connected 原表沒有 caption、thumbnail_url，補 NULL。

{%- set accounts = [
    {'table': 'News',      'dept_scope': 'newsroom',  'has_caption': true},
    {'table': 'Talks',     'dept_scope': 'talks',     'has_caption': false},
    {'table': 'Connected', 'dept_scope': 'connected', 'has_caption': false},
] %}

with
{% for a in accounts %}
{{ a.dept_scope }} as (
  select
    regexp_extract(link, r'/reel/([^/?]+)')         as join_key,
    'Instagram'                                     as platform,
    '{{ a.dept_scope }}'                            as dept_scope,
    `Total Plays`                                   as views,
    `View total time_hrs`                           as watch_time_hours,
    `Reels interactions` + `Shares`                 as engagements,
    cast(null as int64)                             as impressions,
    cast(null as float64)                           as ctr,
    cast(null as string)                            as platform_title,
    release_date                                    as platform_published_date,
    'reels'                                         as orientation,
    true                                            as is_vertical,
    link,
    {%- if a.has_caption %}
    caption,
    thumbnail_url
    {%- else %}
    cast(null as string)                            as caption,
    cast(null as string)                            as thumbnail_url
    {%- endif %}
  from {{ source('instagram', a.table) }}
  where link is not null
  qualify row_number() over (partition by link order by data_date desc) = 1
){{ "," if not loop.last }}
{% endfor %}

{% for a in accounts %}
select * from {{ a.dept_scope }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
