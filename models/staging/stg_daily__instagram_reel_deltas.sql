-- 一列 = 日 × 新聞部單位，IG 每日新增的觀看數，由每支 reel 的累計快照逐支相減而來。
-- 只用於 2026-06-01 前的觀看數（之後改用官方 API）。觀看時數不在這裡算，改讀 Instagram_data.ig_daily_watch_hours
-- （同樣的逐支差分規則，但 2026-10-25 前用人工校正的 Excel 歷史），見 stg_daily__instagram。
--
-- 為什麼不用「帳號總和減前一天」：IG API 偶爾漏回傳或回傳錯誤，帳號總和相減會產生大幅負數：
--   1. 某支影片某天沒回傳、隔天又出現（例：2026-06-29、2026-07-25）→ 一天負、隔天補回。
--   2. 一批影片從某天起永久不再回傳（例：2026-07-14 Newsroom 回傳的影片數少了一半以上）
--      → 總和一次少掉大量數字，7 月時數變成負數。
--   3. 某天一批影片的數字回傳 0、隔天恢復（例：2025-11-28、2026-06-02 的 Newsroom）
--      → 單日出現大幅負數、隔天補回。
--
-- 處理方式：
--   - 逐支相減：每支 reel 只和「它自己上一次出現的快照」相減，漏抓的影片回來時補上期間的增量，
--     永久消失的影片只是不再產生增量，不會把累計值整個扣掉。
--   - 累計值取歷史最大值：累計數字不可能下降，API 回傳 0 或偏低時視為異常而忽略。
--   - 新出現的影片只有在發布日 3 天內才把首次快照的累計值算進來（以及帳號資料的第一天不算），
--     避免追蹤範圍擴大時把舊影片的整個累計值灌進某一天。
--   - 日期 = data_date − 1（快照是當天抓取，反映前一天的累計），與原本的 IG 每日報表一致。
-- 2026-10-13 驗證：正常月份與 daily_ig_summary_report 完全一致，所有日子都沒有負數。

{%- set accounts = [('News', 'newsroom'), ('Talks', 'talks'), ('Connected', 'connected')] %}

with snapshots as (
{% for tbl, scope in accounts %}
  select
    '{{ scope }}'                                   as dept_scope,
    data_date,
    link,
    any_value(release_date)                         as release_date,
    -- 同一天同一支影片偶有重複列（Talks 實測），取最大值
    max(`Total Plays`)                              as plays
  from {{ source('instagram', tbl) }}
  where link is not null
  group by 1, 2, 3
  {% if not loop.last %}union all{% endif %}
{% endfor %}
),
cleaned as (
  select
    dept_scope,
    data_date,
    link,
    release_date,
    max(plays) over reel_history                    as plays
  from snapshots
  window reel_history as (partition by dept_scope, link order by data_date rows between unbounded preceding and current row)
),
with_prev as (
  select
    *,
    lag(plays) over reel                            as prev_plays,
    lag(data_date) over reel                        as prev_date,
    min(data_date) over (partition by dept_scope)   as account_first_date
  from cleaned
  window reel as (partition by dept_scope, link order by data_date)
),
reel_deltas as (
  select
    dept_scope,
    date_sub(data_date, interval 1 day)             as date,
    case
      when prev_date is not null then plays - prev_plays
      when data_date > account_first_date
       and release_date >= date_sub(data_date, interval 3 day) then plays
      else 0
    end                                             as plays_delta
  from with_prev
)
select
  date,
  dept_scope,
  sum(plays_delta)                                  as plays
from reel_deltas
group by date, dept_scope
