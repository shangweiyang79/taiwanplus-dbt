-- walkthrough §3.6 (b)：有主題分類的 VOD 不應該是 Shorts。
-- Shorts 的分類只放在 social_hub.yt_shorts，出現在 vod_category 代表分類流程把 Shorts 混進來了。
-- 名單用 stg_youtube__shorts（API 週更 ∪ yt_shorts）：分類當月名單漏掉的 Short 會被當成橫式分類，
-- 下週名單補上它之後這個測試就會抓到。處理方式見 news_classification_project/deploy/README.md。
select distinct c.vod_id
from {{ ref('vod_category') }} c
join {{ ref('stg_social_hub__post_map') }} p using (vod_id)
join {{ ref('stg_youtube__shorts') }} s
  on p.post_id = s.video_id
where p.platform = 'YouTube'
