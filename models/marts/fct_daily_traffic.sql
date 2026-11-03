-- 一列 = 日 × 新聞部單位 × 平台 × 內容類型（video / story）。新聞部每日流量的主表。
--
-- 每日流量 = 當天實際發生的觀看，不分影片什麼時候發布。問「總體成效」時用這張；
-- 問「哪些影片表現好、為什麼」才用影片層的 fct_social_post_performance。
-- 欄位明確列出，不用 SELECT *，避免 staging 欄位順序改變時 union 靜默錯位。

{%- set cols = [
    'date', 'dept_scope', 'platform', 'content_type',
    'views', 'paid_views', 'engaged_views', 'watch_time_hours', 'source_method',
] %}

{%- set models = [
    'stg_daily__youtube',
    'stg_daily__facebook',
    'stg_daily__x',
    'stg_daily__instagram',
    'stg_daily__instagram_stories',
] %}

-- 帳號暫停收集每日流量後（seed dept_accounts.daily_traffic_to），上游報表仍會補 0（COALESCE），
-- 這些日期在這裡排除：它們是「沒有資料」，不是 0 次觀看（例如 Connected IG 2026-09-29 起）。

with unioned as (
{% for m in models %}
  select {{ cols | join(', ') }}
  from {{ ref(m) }}
  {% if not loop.last %}union all{% endif %}
{% endfor %}
),

collection_end as (
  select dept_scope, platform, daily_traffic_to
  from {{ ref('dept_accounts') }}
  where daily_traffic_to is not null
)

select
  concat(cast(date as string), ':', dept_scope, ':', platform, ':', content_type) as traffic_uid,
  date,
  format_date('%Y-%m', date)                        as year_month,
  date_trunc(date, month)                           as month_start,
  dept_scope,
  platform,
  content_type,
  views,
  paid_views,
  engaged_views,
  watch_time_hours,
  source_method
from unioned u
left join collection_end e using (dept_scope, platform)
where u.date is not null
  and (e.daily_traffic_to is null or u.date <= e.daily_traffic_to)
