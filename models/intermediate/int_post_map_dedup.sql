-- 一列 = 一個 (platform, metrics_key)，對到唯一一支 VOD。
--
-- 給「貼文為主、post_map 為附加維度」的 model 使用（fct_social_post_performance）。
-- post_map 的自然鍵是 (vod_id, platform, post_id)，同一則貼文理論上不該掛兩支 VOD，
-- 但只要有一筆髒資料，那則貼文就會被複製成兩列、觀看數在下游全部加倍。
-- 去重是防呆，不是最佳化。
select
  platform,
  metrics_key,
  vod_id
from {{ ref('stg_social_hub__post_map') }}
where metrics_key is not null
  and vod_id is not null
qualify row_number() over (partition by platform, metrics_key order by vod_id) = 1
