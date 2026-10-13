-- 一列 = 月 × 新聞部單位 × 平台。新聞部「總體成效」的認證匯總表（每日流量）。
--
-- 問總體成效、趨勢、某月總共多少觀看時，直接讀這張，不要自己從明細加總。
-- views 是 KPI：當月實際發生的觀看（IG 含影片類 Stories，YouTube / FB 含付費觀看）。
select
  month_start,
  year_month,
  dept_scope,
  platform,

  sum(views)                                                        as views,
  sum(if(content_type = 'video', views, null))                      as video_views_only,
  sum(if(content_type = 'story', views, null))                      as story_views,
  -- 只有 YouTube 有；輔助參考（KPI 仍是 views），跨 2026-08-27 比較時一併列出
  sum(engaged_views)                                                as engaged_views,
  sum(paid_views)                                                   as paid_views,
  sum(watch_time_hours)                                             as watch_time_hours,

  count(distinct date)                                              as days_with_data,
  -- IG 2026-06 之前是 reel_snapshot_delta（逐支 reel 快照相減，通常偏高 10～20%），之後是 api
  string_agg(distinct source_method order by source_method)         as source_method,
  month_start = date_trunc(current_date('Asia/Taipei'), month)      as is_current_month
from {{ ref('fct_daily_traffic') }}
group by month_start, year_month, dept_scope, platform
