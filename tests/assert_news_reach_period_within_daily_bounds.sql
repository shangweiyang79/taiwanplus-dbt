{{ config(severity='warn') }}

-- 區間 reach 是平台去重後的人數，必須落在 [每日 reach 最大值, 每日 reach 加總] 之間：
--   低於最大值 → 區間對錯天（日界線或 since/until 規則被 Meta 改了）
--   高於加總   → 平台沒有去重，或區間比預期長
-- 只檢查區間內每天都有 day 列的區間。各次抓取時間不同，數字可能還在晚補齊，所以只警告。
with r as (
  select * from {{ ref('stg_news_reach_period') }}
),

daily as (
  select platform, scope, period_end as day, reach
  from r
  where period_type = 'day'
),

bounds as (
  select
    p.period_key, p.reach,
    count(d.day)   as days_with_data,
    p.days_covered,
    max(d.reach)   as max_daily,
    sum(d.reach)   as sum_daily
  from r p
  join daily d
    on d.platform = p.platform and d.scope = p.scope
   and d.day between p.period_start and p.period_end
  where p.period_type != 'day'
  group by p.period_key, p.reach, p.days_covered
)

select *
from bounds
where days_with_data = days_covered
  and (reach < max_daily or reach > sum_daily)
