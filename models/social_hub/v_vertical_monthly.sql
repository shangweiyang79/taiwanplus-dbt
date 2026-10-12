-- 相容 view：直式短影音的逐月成效（只有 Newsroom），完全不經過 post_map。
-- 這是「給同事看的那張」，刻意只保留觀看數：觀看時長和互動數在三個平台的定義都不同。
--
-- 已知限制：
--   1. 沒有 vod_id，所以沒有主題分類 / tag。要依主題分析請用 v_vertical_category_performance。
--   2. 跨平台比絕對值沒有意義（FB 播放滿 3 秒、IG Total Plays、YouTube views），只能看各平台自己的趨勢。
--   3. YouTube Shorts 靠 yt_shorts 清單判斷，完整度取決於最近一次有沒有重新匯出。
--   4. X 沒有直式 / 橫式資訊，不在這張表。
--
-- 舊版直接讀原表；這裡改讀 staging，IG 取最新快照等邏輯只維護一份，結果相同。
with unioned as (
  select platform, orientation, platform_published_date as publish_date, views
  from {{ ref('stg_facebook__videos') }}
  where orientation = 'reels'

  union all

  select platform, orientation, platform_published_date, views
  from {{ ref('stg_instagram__reels') }}
  where dept_scope = 'newsroom'

  union all

  select platform, orientation, platform_published_date, views
  from {{ ref('stg_youtube__videos') }}
  where dept_scope = 'newsroom' and orientation = 'shorts'
)
select
  format_date('%Y-%m', publish_date)                      as year_month,
  date_trunc(publish_date, month)                         as month_start,
  platform,
  orientation,

  count(*)                                                as post_count,
  sum(views)                                              as total_views,

  -- 平均與中位數要一起看：少數爆量貼文就能把平均拉高一個量級（實測 FB reels 平均約為中位數的 9 倍）
  safe_divide(sum(views), count(*))                       as avg_views_per_post,
  -- 近似中位數，每次執行結果可能略有不同（見 v_tag_platform_summary 的說明）
  approx_quantiles(views, 2)[offset(1)]                   as median_views_per_post,
  max(views)                                              as max_views
from unioned
where publish_date is not null
group by year_month, month_start, platform, orientation
