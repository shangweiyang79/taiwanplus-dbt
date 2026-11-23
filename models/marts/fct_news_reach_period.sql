-- 一列 = Newsroom 在 FB / IG 某個區間的不重複觸及人數。reach 不能 SUM，要哪個區間就取哪個 period_type。
select
  period_key,
  platform,
  dept_scope,
  scope,
  period_type,
  period_start,
  period_end,
  days_covered,
  is_full_period,
  reach,
  source_metric,
  fetched_at
from {{ ref('stg_news_reach_period') }}
