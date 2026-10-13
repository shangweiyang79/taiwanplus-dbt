-- 每日流量月表的總量必須與每日明細完全相同（每個月 × 單位 × 平台）。
with agg as (
  select month_start, dept_scope, platform, views
  from {{ ref('agg_news_dept_daily_traffic_monthly') }}
),
fct as (
  select month_start, dept_scope, platform, sum(views) as views
  from {{ ref('fct_daily_traffic') }}
  group by 1, 2, 3
)
select month_start, dept_scope, platform, agg.views as agg_views, fct.views as fct_views
from agg
full join fct using (month_start, dept_scope, platform)
where agg.views is distinct from fct.views
