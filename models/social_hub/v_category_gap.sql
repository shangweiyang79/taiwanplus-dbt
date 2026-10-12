-- 相容 view：post_map 裡有、但 vod_category 沒有分類的 VOD，一列一支（只有 Newsroom）。
-- 每月檢查用（walkthrough §3.6 (e)）。
--
-- 「沒有分類」多數是正常的，所以分類別看：
--   shorts     Shorts，分類在 social_hub.yt_shorts（刻意的分工）
--   newscast   newscasts / 長片，雲端分類流程刻意排除
--   no_length  YouTube 影片表還沒收錄，下次更新後會自動歸入其他類
--   gap        真正漏網，只有這一類需要人工追查
--
-- 300 秒門檻：Shorts 最長 181 秒、newscasts 幾乎都是 901 或 1621 秒，181~600 秒之間沒有影片。
-- 節目長度結構改變時要重新檢查這個數字。
with youtube as (
  select join_key as video_id, video_length
  from {{ ref('stg_youtube__videos') }}
  where dept_scope = 'newsroom'
),
missing as (
  select
    p.vod_id,
    p.publish_date,
    any_value(p.title)                                  as title,
    string_agg(distinct p.platform order by p.platform) as platforms,
    -- 只要該 VOD 有任何一則 YouTube 貼文在 Shorts 清單上，就算 Shorts
    logical_or(s.video_id is not null)                  as is_short,
    max(y.video_length)                                 as video_length
  from {{ ref('stg_social_hub__post_map') }} p
  left join {{ ref('vod_category') }} c using (vod_id)
  left join {{ source('social_hub', 'yt_shorts') }} s
    on p.platform = 'YouTube' and p.post_id = s.video_id
  left join youtube y
    on p.platform = 'YouTube' and p.post_id = y.video_id
  where c.vod_id is null
  group by p.vod_id, p.publish_date
)
select
  vod_id,
  publish_date,
  format_date('%Y-%m', publish_date) as year_month,
  title,
  platforms,
  video_length,
  case
    when is_short              then 'shorts'
    when video_length is null  then 'no_length'
    when video_length > 300    then 'newscast'
    else 'gap'
  end as bucket
from missing
