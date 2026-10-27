-- IG 每日流量的觀看時數，各月總數必須等於 Instagram_data.ig_daily_watch_hours（與 IG 每日報表、Excel 歷史同一份數字）。
-- 和 assert_daily_traffic_matches_sources 一樣，刻意不重用 staging，用獨立的 SQL 重算。
with expected as (
  select date_trunc(date, month) as month_start,
         case account when 'News' then 'newsroom' when 'Talks' then 'talks' when 'Connected' then 'connected' end as dept_scope,
         round(sum(watch_hours), 6) as watch_hours
  from {{ source('instagram', 'ig_daily_watch_hours') }}
  where date >= '2025-08-01' and granularity = 'day' and account in ('News', 'Talks', 'Connected')
  group by 1, 2
),
actual as (
  select month_start, dept_scope, round(sum(watch_time_hours), 6) as watch_hours
  from {{ ref('fct_daily_traffic') }}
  where platform = 'Instagram' and content_type = 'video' and watch_time_hours is not null
  group by 1, 2
)
select month_start, dept_scope, e.watch_hours as expected_watch_hours, a.watch_hours as actual_watch_hours
from expected e
full join actual a using (month_start, dept_scope)
where e.watch_hours is distinct from a.watch_hours
