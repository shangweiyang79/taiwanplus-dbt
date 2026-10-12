-- 認證匯總表的總量必須與明細表完全相同（每個單位 × 平台）。
with agg as (
  select dept_scope, platform, sum(video_views) as v, sum(post_count) as n
  from {{ ref('agg_news_dept_social_monthly') }}
  group by 1, 2
),
fct as (
  select dept_scope, platform, sum(views) as v, count(*) as n
  from {{ ref('fct_social_post_performance') }}
  group by 1, 2
)
select dept_scope, platform, agg.v as agg_views, fct.v as fct_views, agg.n as agg_posts, fct.n as fct_posts
from agg
full join fct using (dept_scope, platform)
where agg.v is distinct from fct.v or agg.n is distinct from fct.n
