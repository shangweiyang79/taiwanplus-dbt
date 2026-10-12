-- 主表裡每一種（單位, 平台）組合都必須登記在 seed dept_accounts。
-- 新接一個帳號時若忘了更新對照表，這個測試會失敗，避免定義文件與資料脫節。
select distinct f.dept_scope, f.platform
from {{ ref('fct_social_post_performance') }} f
left join {{ ref('dept_accounts') }} a
  on f.dept_scope = a.dept_scope and f.platform = a.platform
where a.dept_scope is null
