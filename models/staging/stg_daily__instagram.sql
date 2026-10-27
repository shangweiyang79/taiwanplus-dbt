-- 一列 = 日 × 新聞部單位，IG 每日流量（不含 Stories，Stories 在 stg_daily__instagram_stories）。
--
-- 觀看數：
--   2026-06-01 之前：逐支 reel 快照相減（stg_daily__instagram_reel_deltas，source_method = reel_snapshot_delta）。
--                    和之後的官方 API 相比通常偏高 10～20%（Total Plays 與 API views 的定義差異）。
--   2026-06-01 起：官方 API（daily_ig_summary_report_new，source_method = api）。
-- 觀看時數：API 不提供，所有期間都讀 Instagram_data.ig_daily_watch_hours，與 IG 每日報表同一份數字：
--   2026-10-25 前是人工校正過的 IG_daily_traffic.xlsx 歷史，2026-10-26 起由該 view 逐支 reel 差分計算，不會有負數。
--   定義見 TaiwanPlus_api/sql/ig_daily_watch_hours.sql。
-- 起始日 2025-08-01，與原本的 IG 每日報表一致。Program（IG Social）不屬於新聞部，不取。

{%- set cutover = "date '2026-06-01'" %}
{%- set accounts = [('News', 'newsroom'), ('Talks', 'talks'), ('Connected', 'connected')] %}

with reel as (
  select date, dept_scope, plays
  from {{ ref('stg_daily__instagram_reel_deltas') }}
  where date >= date '2025-08-01' and date < {{ cutover }}
),
api as (
{% for col, scope in accounts %}
  select
    Date                                            as date,
    '{{ scope }}'                                   as dept_scope,
    `IG {{ col }} VV`                               as views,
    `IG {{ col }} Ads VV`                           as paid_views
  from {{ source('instagram', 'daily_ig_summary_report_new') }}
  where Date >= {{ cutover }}
  {% if not loop.last %}union all{% endif %}
{% endfor %}
),
wh as (
  select
    date,
    case account {% for col, scope in accounts %}when '{{ col }}' then '{{ scope }}' {% endfor %}end as dept_scope,
    watch_hours
  from {{ source('instagram', 'ig_daily_watch_hours') }}
  where date >= date '2025-08-01'
    and granularity = 'day'
    and account in ({% for col, scope in accounts %}'{{ col }}'{% if not loop.last %}, {% endif %}{% endfor %})
),
views as (
  select date, dept_scope, plays as views, cast(null as int64) as paid_views from reel
  union all
  select date, dept_scope, views, paid_views from api
)
select
  coalesce(v.date, w.date)                          as date,
  coalesce(v.dept_scope, w.dept_scope)              as dept_scope,
  'Instagram'                                       as platform,
  'video'                                           as content_type,
  v.views,
  v.paid_views,
  cast(null as int64)                               as engaged_views,
  w.watch_hours                                     as watch_time_hours,
  if(coalesce(v.date, w.date) < {{ cutover }}, 'reel_snapshot_delta', 'api') as source_method
from views v
full join wh w
  on v.date = w.date and v.dept_scope = w.dept_scope
