-- BigQuery 成本防線：近 7 天（台北時間，含今天）asia-east1 的計費掃描量不能超過門檻。
--
-- 為什麼：2026-11 youtube-owner-chain 被 owner transfer 的修正寫入一天觸發 4–12 次，
-- 一個月掃了 2.7 TiB，等到帳單出來才發現。有這個 test 的話 11/1 就會寄信。
--
-- 為什麼看 7 天而不是 1 天：開發、測 chatbox 的日子單日會到 100+ GiB（2026-10），
-- 單日門檻會一直誤報；7 天總量看的是「持續變貴」。
-- 門檻 500 GiB/7 天 ≈ 每月 2.1 TiB ≈ 扣掉 1 TiB 免費額度後 USD 8/月。
-- 實測（滾動 7 天）：2026-08、09 最高 76 GiB；10 月底（開發 + 鏈上線）最高 554；11 月 651–1037。
--
-- 失敗時：看回傳的 top_users 是誰在掃。是自己開發 → 知道就好；是服務帳號 → 查它的觸發次數。
-- 查法見 orchestration/README.md「成本防線」。
--
-- 只在每日檢查跑（daily_checks.sh 設 DBT_COST_CHECK=true）：CI / CD 不跑，
-- 避免成本高的時候連修正都部署不上去。需要 dbt-runner 有 roles/bigquery.resourceViewer（jobs.listAll）。
-- SCRIPT 父 job 的 bytes 是子 job 的加總，排除以免重複計算。
{{ config(enabled = env_var('DBT_COST_CHECK', 'false') == 'true') }}

{% set limit_gib = var('bq_7d_scan_limit_gib', 500) %}
-- 限流（PR #16）11/26 上線，之前的日子不算，否則前 7 天每天都會報錯；2026-12-03 以後這個參數就沒有作用了。
-- 視窗不滿 7 天時門檻**不**按天數縮小：第一版縮小後，第一天的門檻等於 71 GiB 的單日門檻，
-- 11/27 開發日（3 次 PR CI、2 次 CD、強制重建，共 118 GiB）就誤報了兩次。前幾天寬鬆一點沒關係。
{% set since = var('bq_scan_check_since', '2026-11-27') %}

with bounds as (
  select
    greatest(date_sub(current_date('Asia/Taipei'), interval 6 day), date '{{ since }}') as start_date
),

jobs as (
  select
    user_email,
    total_bytes_billed / pow(1024, 3) as gib
  from `{{ target.database }}`.`region-asia-east1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  where creation_time >= (select timestamp(start_date, 'Asia/Taipei') from bounds)
    and statement_type is distinct from 'SCRIPT'
),

by_user as (
  select user_email, sum(gib) as gib
  from jobs
  group by user_email
),

total as (
  select
    any_value(b.start_date) as since_date,
    any_value(date_diff(current_date('Asia/Taipei'), b.start_date, day) + 1) as days,
    round(sum(u.gib), 1) as scanned_gib,
    {{ limit_gib }} as limit_gib,
    -- 照這段期間的速度，一個月的 BQ 查詢費（asia-east1 USD 7.1875/TiB，扣 1 TiB 免費）
    round(greatest(sum(u.gib) / any_value(date_diff(current_date('Asia/Taipei'), b.start_date, day) + 1) * 30 / 1024 - 1, 0) * 7.1875, 1)
      as est_usd_per_month,
    string_agg(format('%s %.0f GiB', u.user_email, u.gib), '; ' order by u.gib desc limit 3) as top_users
  from by_user as u
  cross join bounds as b
)

select *
from total
where scanned_gib > limit_gib
