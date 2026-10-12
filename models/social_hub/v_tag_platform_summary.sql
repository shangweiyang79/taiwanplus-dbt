-- 相容 view：月 × tag × 平台的匯總（只有 Newsroom），回答「各平台哪些 tag 表現最好」。
--
-- 一列 = VOD × tag 的展開，所以跨 tag 加總會重複計算，只能比 tag 之間的平均 / 中位數。
-- 排行榜務必加樣本數門檻（例如 HAVING COUNT(DISTINCT vod_id) >= 10）。
-- 各平台「觀看」定義不同，比較同一個 tag 在哪個平台較好時，請看各平台內部的排名。
select
  format_date('%Y-%m', p.publish_date)                    as year_month,
  date_trunc(p.publish_date, month)                       as month_start,
  tag,
  p.platform,

  count(distinct p.vod_id)                                as video_count,
  count(*)                                                as post_count,
  sum(p.views)                                            as total_views,

  safe_divide(sum(p.views), count(distinct p.vod_id))     as avg_views_per_video,
  -- 近似中位數：每次執行結果可能略有不同，且可能偏離精確值（2026-10-12 實測 2026-05 Taiwan × Facebook
  -- 舊 view 比精確值低約 7%）。沿用舊寫法以維持相容，之後可考慮改成精確中位數。
  approx_quantiles(p.views, 2)[offset(1)]                 as median_views_per_video,
  safe_divide(sum(p.engagements), sum(p.views))           as engagement_rate
from {{ ref('v_vod_social_performance') }} p
join {{ ref('vod_category') }} c
  on p.vod_id = c.vod_id
cross join unnest(c.tags) as tag
where p.has_metrics
group by year_month, month_start, tag, platform
