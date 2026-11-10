-- 一列 = 一支 YouTube Short。「這支影片是不是 Shorts」的唯一入口，下游一律 ref 這裡，不要直接讀 yt_shorts。
-- 不能用影片長度判斷：Shorts 與一般新聞短片的長度分布完全重疊。
--
-- 名單是兩個來源的聯集：
--   api       YouTube_data.video_metadata，creator_content_type = 'shorts'（Analytics API）。
--             Cloud Run Job yt-weekly 每週一、每月 4 號更新，涵蓋新聞部 4 個頻道，2026-01-01 起。
--   workbook  social_hub.yt_shorts，每月 5 號後從活頁簿整表覆蓋。只有 News / Explains，
--             但有 2024 起的歷史，也有 API 看不到的私人影片。
-- 分類欄位（new_category、bite_reel、tags）只有 workbook 有：當月的 Shorts 先以 api_only 出現、分類為 NULL，
-- 每月分類貼回活頁簿並跑 yt_shorts_bq.py 之後變成 both。
with api as (
  select video_id, channel_id, channel_key, dept_scope, title, publish_date_tpe
  from {{ source('youtube_data', 'video_metadata') }}
  where creator_content_type = 'shorts'
),

workbook as (
  select video_id, title, new_category, confidence_score, bite_reel, bite_reel_src, tags, tags_text
  from {{ source('social_hub', 'yt_shorts') }}
)

select
  coalesce(a.video_id, w.video_id)                     as video_id,
  a.channel_id,
  a.channel_key,
  a.dept_scope,
  -- 活頁簿的標題優先，與改版前的 view 一致；活頁簿還沒有的才用 API 標題
  coalesce(w.title, a.title)                           as title,
  a.publish_date_tpe,
  w.new_category,
  w.confidence_score,
  w.bite_reel,
  w.bite_reel_src,
  w.tags,
  w.tags_text,
  w.video_id is not null                               as is_labelled,
  case
    when a.video_id is null then 'workbook_only'
    when w.video_id is null then 'api_only'
    else 'both'
  end                                                  as list_source
from api a
full outer join workbook w
  on a.video_id = w.video_id
