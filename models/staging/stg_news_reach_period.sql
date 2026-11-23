-- 一列 = Newsroom 在某平台、某區間的不重複觸及人數（reach），只取每個區間最新一次抓取。
-- 原表每天重抓最近 7 天結束的區間並保留每個版本（數字會晚補齊），所以這裡用 fetched_at 取最新。
-- reach 是人數：同一個人跨日、跨區間、跨 scope、跨平台都會重複，任何方向都不能 SUM。
with unioned as (
  select 'Facebook' as platform, account, scope, period_type, period_start, period_end,
         days_covered, is_full_period, reach, metric, fetched_at
  from {{ source('facebook', 'fb_news_reach_period') }}
  union all
  select 'Instagram' as platform, account, scope, period_type, period_start, period_end,
         days_covered, is_full_period, reach, metric, fetched_at
  from {{ source('instagram', 'ig_news_reach_period') }}
)

select
  platform,
  'newsroom'                                         as dept_scope,
  scope,
  period_type,
  period_start,
  period_end,
  days_covered,
  is_full_period,
  reach,
  metric                                             as source_metric,
  fetched_at,
  concat(platform, ':', scope, ':', period_type, ':', cast(period_start as string), ':',
         cast(period_end as string))                 as period_key
from unioned
qualify row_number() over (
  partition by platform, account, scope, period_type, period_start, period_end
  order by fetched_at desc
) = 1
