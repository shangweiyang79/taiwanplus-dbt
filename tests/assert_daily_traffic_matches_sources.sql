-- 每日流量各月總數必須等於「直接加總來源表」的結果。
-- 這裡刻意不重用 staging，用獨立的 SQL 重算一次，確保 staging 的轉換沒有寫錯。
with expected as (
  select date_trunc(parse_date('%Y%m%d', date), month) as month_start,
         case channel_id when 'UCSyJ1WvirdmrMY8rpnT41LA' then 'talks'
                         when 'UC1oUAE7Bj5o6zEGm0Hq4BdA' then 'connected'
                         else 'newsroom' end as dept_scope,
         'YouTube' as platform, sum(total_views) as views
  from {{ source('youtube', 'daily_detailed_summary') }}
  where channel_id in ('UCCJBSLNtozkO-NqjpPZujiQ', 'UC7c6rvyAZLpKGk8ttVnpnLA', 'UComl1gAjeqAAiRR6s3ae73w',
                       'UCSyJ1WvirdmrMY8rpnT41LA', 'UC1oUAE7Bj5o6zEGm0Hq4BdA')
  group by 1, 2, 3

  union all
  select date_trunc(date, month), 'newsroom', 'Facebook', sum(page_video_views)
  from {{ source('facebook', 'TaiwanPlus_news') }} group by 1

  union all
  select date_trunc(date, month), 'newsroom', 'X', sum(views)
  from {{ source('x', 'daily_traffic') }} group by 1

  union all
  select date_trunc(d, month), dept_scope, 'Instagram', sum(v)
  from (
    -- IG 只比 2026-06-01 起的 API 觀看數；之前的觀看數由 dbt 逐支 reel 相減計算（見 stg_daily__instagram_reel_deltas）
    select Date as d, 'newsroom' as dept_scope, `IG News VV` as v from {{ source('instagram', 'daily_ig_summary_report_new') }} where Date >= '2026-06-01'
    union all select Date, 'talks', `IG Talks VV` from {{ source('instagram', 'daily_ig_summary_report_new') }} where Date >= '2026-06-01'
    union all select Date, 'connected', `IG Connected VV` from {{ source('instagram', 'daily_ig_summary_report_new') }} where Date >= '2026-06-01'
    union all select date, 'newsroom', `IG News Story VV` from {{ source('instagram', 'ig_stories_pivot_daily') }}
    union all select date, 'talks', `IG Talks Story VV` from {{ source('instagram', 'ig_stories_pivot_daily') }}
    union all select date, 'connected', `IG Connected Story VV` from {{ source('instagram', 'ig_stories_pivot_daily') }}
  )
  group by 1, 2, 3
),
actual as (
  select month_start, dept_scope, platform, sum(views) as views
  from {{ ref('fct_daily_traffic') }}
  -- 與 expected 同範圍：IG 只比 2026-06 起
  where not (platform = 'Instagram' and content_type = 'video' and date < '2026-06-01')
  group by 1, 2, 3
)
select month_start, dept_scope, platform, e.views as expected_views, a.views as actual_views
from expected e
full join actual a using (month_start, dept_scope, platform)
where e.views is distinct from a.views
