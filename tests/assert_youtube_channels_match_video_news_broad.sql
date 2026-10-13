-- seed youtube_channels 的頻道 → 單位對照，必須與 video_news_broad 的 dept_scope 一致，
-- 避免每日流量層和影片層把同一個頻道歸到不同單位。
select distinct b.channel_id, b.dept_scope as broad_dept_scope, c.dept_scope as seed_dept_scope
from {{ source('youtube', 'video_news_broad') }} b
left join {{ ref('youtube_channels') }} c using (channel_id)
where c.dept_scope is distinct from b.dept_scope
