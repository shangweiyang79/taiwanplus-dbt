-- walkthrough §3.6 (c)：vod_category.publish_date 必須等於 vod_id 前 6 碼（yymmdd）。
select vod_id, publish_date
from {{ ref('vod_category') }}
where publish_date != parse_date('%y%m%d', substr(vod_id, 1, 6))
