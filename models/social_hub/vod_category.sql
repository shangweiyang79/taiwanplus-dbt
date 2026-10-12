-- 一列 = 一支 VOD（只有 Newsroom，靠 post_map 的 YouTube 貼文對回 vod_id）。
-- 建在雲端分類結果 video_news_category 上，雲端流程更新後自動跟著更新。
--
-- 三個刻意的取捨：
--   1. 排除 source = 'shorts_gemini'：Shorts 分類只放 social_hub.yt_shorts。
--   2. publish_date 用 vod_id 前 6 碼推導，不用雲端的 YouTube 發布日（實測約 7% 不同）。
--   3. content_category 來自 vod_content_category（CMS 匯出），新 VOD 可能為 NULL。
with src as (
  select
    p.vod_id,
    -- grain 已是 vod_id 且實測 0 筆分類衝突，ANY_VALUE 安全
    any_value(c.video_id)      as video_id,
    any_value(c.new_category)  as new_category,
    any_value(c.confidence)    as confidence_score,
    any_value(c.program)       as program,
    any_value(c.tags)          as tags_raw,
    any_value(c.source)        as classifier_source,
    any_value(c.model_version) as model_version,
    max(c.run_date)            as run_date
  from {{ ref('stg_social_hub__post_map') }} p
  join {{ source('youtube', 'video_news_category') }} c
    on p.platform = 'YouTube' and p.post_id = c.video_id
  where c.source != 'shorts_gemini'
  group by p.vod_id
),
-- 寫成「攤平 -> JOIN -> 重新聚合」，不要改成 SELECT 清單裡的 ARRAY(...) 子查詢：
-- 那種寫法 BigQuery 無法去相關化，任何對 tags 做 UNNEST 的下游查詢都會報錯。
tag_norm as (
  select
    s.vod_id,
    array_agg(distinct coalesce(a.canonical, t) order by coalesce(a.canonical, t)) as tags
  from src s
  cross join unnest(s.tags_raw) as t
  left join {{ source('social_hub', 'tag_aliases') }} a
    on lower(trim(t)) = a.alias_lower
  group by s.vod_id
)
select
  s.vod_id,
  parse_date('%y%m%d', substr(s.vod_id, 1, 6))          as publish_date,
  -- 來源有 'Dc Insiders' / 'DC Insiders' 兩種寫法
  case lower(s.program)
    when 'dc insiders' then 'DC Insiders'
    else s.program
  end                                                   as program,
  cc.content_category,
  s.new_category,
  s.confidence_score,
  -- CROSS JOIN UNNEST 會讓沒有 tag 的 VOD 消失，補成空陣列（REPEATED 欄位不吃 NULL）
  coalesce(tn.tags, [])                                 as tags,
  s.tags_raw,
  -- Looker Studio 處理不了 REPEATED 欄位
  array_to_string(coalesce(tn.tags, []), ', ')          as tags_text,
  s.video_id,
  s.classifier_source,
  s.model_version,
  s.run_date
from src s
left join tag_norm tn using (vod_id)
left join {{ source('social_hub', 'vod_content_category') }} cc
  using (vod_id)
