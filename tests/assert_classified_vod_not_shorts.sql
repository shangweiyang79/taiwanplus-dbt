-- walkthrough §3.6 (b)：有主題分類的 VOD 不應該是 Shorts。
-- Shorts 的分類只放在 social_hub.yt_shorts，出現在 vod_category 代表分類流程把 Shorts 混進來了。
select distinct c.vod_id
from {{ ref('vod_category') }} c
join {{ ref('stg_social_hub__post_map') }} p using (vod_id)
join {{ source('social_hub', 'yt_shorts') }} s
  on p.post_id = s.video_id
where p.platform = 'YouTube'
