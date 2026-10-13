-- 一列 = 日 × 新聞部單位，IG 每日流量（不含 Stories，Stories 在 stg_daily__instagram_stories）。
--
-- 2026-06-01 換算法：
--   之前：daily_ig_summary_report，各帳號每天 Total Plays 總和減前一天（snapshot_delta）。
--         和官方 API 重疊期間通常偏高 10～20%，偶有負數（快照異常）。
--   之後：daily_ig_summary_report_new，觀看取官方 API（api）；時數兩者都是快照相減。
-- Program（IG Social）不屬於新聞部，不取。

{%- set cutover = "date '2026-06-01'" %}
{%- set accounts = [('News', 'newsroom'), ('Talks', 'talks'), ('Connected', 'connected')] %}

{% for col, scope in accounts %}
select
  Date                                              as date,
  '{{ scope }}'                                     as dept_scope,
  'Instagram'                                       as platform,
  'video'                                           as content_type,
  `IG {{ col }} VV`                                 as views,
  `IG {{ col }} Ads VV`                             as paid_views,
  cast(null as int64)                               as engaged_views,
  `IG {{ col }} WH`                                 as watch_time_hours,
  'snapshot_delta'                                  as source_method
from {{ source('instagram', 'daily_ig_summary_report') }}
where Date < {{ cutover }}

union all

select
  Date,
  '{{ scope }}',
  'Instagram',
  'video',
  `IG {{ col }} VV`,
  `IG {{ col }} Ads VV`,
  cast(null as int64),
  `IG {{ col }} WH`,
  'api'
from {{ source('instagram', 'daily_ig_summary_report_new') }}
where Date >= {{ cutover }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
