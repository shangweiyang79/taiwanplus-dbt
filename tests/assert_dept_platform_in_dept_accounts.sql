-- 主表（影片層與每日流量層）裡每一種（單位, 平台）組合都必須登記在 seed dept_accounts。
-- 新接一個帳號時若忘了更新對照表，這個測試會失敗，避免定義文件與資料脫節。
with combos as (
  select distinct dept_scope, platform from {{ ref('fct_social_post_performance') }}
  union distinct
  select distinct dept_scope, platform from {{ ref('fct_daily_traffic') }}
)
select c.dept_scope, c.platform
from combos c
left join {{ ref('dept_accounts') }} a
  on c.dept_scope = a.dept_scope and c.platform = a.platform
where a.dept_scope is null
