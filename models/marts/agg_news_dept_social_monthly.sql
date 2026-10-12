-- 一列 = 月 × 新聞部單位 × 平台。新聞部社群成效的「認證匯總表」。
--
-- 給 AI chatbot 與報表直接讀的標準答案：常見問題（新聞部 / 各單位 / 各平台的逐月成效）
-- 直接查這張，不用自己從明細 SUM，避免算錯。計算方式與 semantic layer 的 metric 定義相同。
-- 自訂期間（例如某一週）或要切主題、節目時，才回到 fct_social_post_performance。
select
  month_start,
  year_month,
  dept_scope,
  platform,

  sum(views)                                              as video_views,
  count(post_uid)                                         as post_count,
  sum(watch_time_hours)                                   as watch_time_hours,
  sum(engagements)                                        as engagements,
  safe_divide(sum(engagements), sum(views))               as engagement_rate,
  safe_divide(sum(views), count(post_uid))                as avg_views_per_post,
  max(views)                                              as max_views_per_post,

  -- 數字是累計值：當月與上個月的影片累計天數較少，天生偏低，不代表成效衰退
  month_start = date_trunc(current_date('Asia/Taipei'), month)   as is_current_month,
  date_diff(current_date('Asia/Taipei'), last_day(month_start), day) as days_since_month_end
from {{ ref('fct_social_post_performance') }}
group by month_start, year_month, dept_scope, platform
