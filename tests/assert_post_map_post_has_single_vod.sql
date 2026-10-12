{{ config(severity='warn') }}

-- 同一則貼文不該掛到兩支 VOD。下游已在 int_post_map_dedup 防呆去重，所以只警告不中斷，
-- 但出現時代表 CMS 的 Social Media Feed 有髒資料，值得回報。
select platform, metrics_key, count(distinct vod_id) as vod_count
from {{ ref('stg_social_hub__post_map') }}
where metrics_key is not null and vod_id is not null
group by platform, metrics_key
having count(distinct vod_id) > 1
