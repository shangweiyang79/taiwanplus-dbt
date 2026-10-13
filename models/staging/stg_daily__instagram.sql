-- 一列 = 日 × 新聞部單位，IG 每日流量（不含 Stories，Stories 在 stg_daily__instagram_stories）。
--
-- 觀看數：
--   2026-06-01 之前：逐支 reel 快照相減（stg_daily__instagram_reel_deltas，source_method = reel_snapshot_delta）。
--                    和之後的官方 API 相比通常偏高 10～20%（Total Plays 與 API views 的定義差異）。
--   2026-06-01 起：官方 API（daily_ig_summary_report_new，source_method = api）。
-- 觀看時數：API 不提供，所有期間都用逐支 reel 快照相減。
--   不用 daily_ig_summary_report(_new) 的時數欄位：它們是帳號總和相減，API 漏抓時會出現大幅負數
--   （2026-07 Newsroom 出現大幅負數），處理方式見 stg_daily__instagram_reel_deltas。
-- 起始日 2025-08-01，與原本的 IG 每日報表一致。Program（IG Social）不屬於新聞部，不取。

{%- set cutover = "date '2026-06-01'" %}
{%- set accounts = [('News', 'newsroom'), ('Talks', 'talks'), ('Connected', 'connected')] %}

with reel as (
  select date, dept_scope, plays, watch_hours
  from {{ ref('stg_daily__instagram_reel_deltas') }}
  where date >= date '2025-08-01'
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
)
select
  coalesce(r.date, a.date)                          as date,
  coalesce(r.dept_scope, a.dept_scope)              as dept_scope,
  'Instagram'                                       as platform,
  'video'                                           as content_type,
  if(coalesce(r.date, a.date) < {{ cutover }}, r.plays, a.views) as views,
  a.paid_views,
  cast(null as int64)                               as engaged_views,
  r.watch_hours                                     as watch_time_hours,
  if(coalesce(r.date, a.date) < {{ cutover }}, 'reel_snapshot_delta', 'api') as source_method
from reel r
full join api a
  on r.date = a.date and r.dept_scope = a.dept_scope
