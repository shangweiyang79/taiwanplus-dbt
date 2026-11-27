-- BigQuery 成本防線：近 7 天（台北時間，含今天）asia-east1「自動化」的計費掃描量不能超過門檻。
--
-- 為什麼：2026-11 youtube-owner-chain 被 owner transfer 的修正寫入一天觸發 4–12 次，
-- 一個月掃了 2.7 TiB，等到帳單出來才發現。這個 test 要抓的是「自動化自己失控」。
--
-- 只算自動化：服務帳號 + 所有 BQ 排程查詢（有些掛在個人帳號下，用 job_id 前綴判斷）。
-- 不算：人手動的查詢、CI（dbt-ci）、CD（dbt-prod、dbt-deployer）。開發日一天就 100+ GiB
-- （一次 PR CI 15–25、一次 CD 10–20），連續幾天開發就會誤報，而且那是自己知道的花費。
--
-- 門檻 450 GiB/7 天。依據（2026-11-27 實測 90 天的各類別 7 天量）：
--   限流後預估平常一週約 260（yt-chain ~60、dbt-runner ~150、排程查詢 26、ingestion 12、其他）；
--   所有類別最大值同一週疊在一起約 510（極少）；11 月失控時自動化每週 600–890。
--   失控開始後約 2–3 天累積到門檻就會寄信。2026-12-03 滿一週實測後，門檻改成實際平常週的約 1.7 倍。
--
-- 失敗時：看回傳的 top_accounts 是誰在掃，再查它被觸發幾次（orchestration/README.md「成本防線」）。
--
-- 只在每日檢查跑（daily_checks.sh 設 DBT_COST_CHECK=true）：CI / CD 不跑，
-- 避免成本高的時候連修正都部署不上去。需要 dbt-runner 有 roles/bigquery.resourceViewer（jobs.listAll）。
-- SCRIPT 父 job 的 bytes 是子 job 的加總，排除以免重複計算。
{{ config(enabled = env_var('DBT_COST_CHECK', 'false') == 'true') }}

{% set limit_gib = var('bq_7d_scan_limit_gib', 450) %}
-- 限流（PR #16）11/26 上線，之前的日子不算，否則前 7 天每天都會報錯；2026-12-03 以後這個參數就沒有作用了。
-- 視窗不滿 7 天時門檻不縮小：第一版縮小後第一天門檻只剩 71 GiB，11/27 開發日就誤報了兩次。
{% set since = var('bq_scan_check_since', '2026-11-27') %}

with bounds as (
  select
    greatest(date_sub(current_date('Asia/Taipei'), interval 6 day), date '{{ since }}') as start_date
),

jobs as (
  select
    if(starts_with(job_id, 'scheduled_query'), 'scheduled_query:' || user_email, user_email) as account,
    total_bytes_billed / pow(1024, 3) as gib
  from `{{ target.database }}`.`region-asia-east1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  where creation_time >= (select timestamp(start_date, 'Asia/Taipei') from bounds)
    and statement_type is distinct from 'SCRIPT'
    and (
      starts_with(job_id, 'scheduled_query')
      or (
        ends_with(user_email, 'gserviceaccount.com')
        and split(user_email, '@')[offset(0)] not in ('dbt-ci', 'dbt-prod', 'dbt-deployer')
      )
    )
),

by_account as (
  select account, sum(gib) as gib
  from jobs
  group by account
),

total as (
  select
    any_value(b.start_date) as since_date,
    any_value(date_diff(current_date('Asia/Taipei'), b.start_date, day) + 1) as days,
    round(sum(a.gib), 1) as automation_gib,
    {{ limit_gib }} as limit_gib,
    -- 只看自動化、照這段期間的速度，一個月的 BQ 查詢費（asia-east1 USD 7.1875/TiB，扣 1 TiB 免費）
    round(greatest(sum(a.gib) / any_value(date_diff(current_date('Asia/Taipei'), b.start_date, day) + 1) * 30 / 1024 - 1, 0) * 7.1875, 1)
      as est_usd_per_month,
    string_agg(format('%s %.0f GiB', a.account, a.gib), '; ' order by a.gib desc limit 3) as top_accounts
  from by_account as a
  cross join bounds as b
)

select *
from total
where automation_gib > limit_gib
