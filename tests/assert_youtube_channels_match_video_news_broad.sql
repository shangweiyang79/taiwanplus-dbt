-- seed youtube_channels 必須與 video_news_broad 一致：
-- 1. 頻道 → 單位對照相同，避免每日流量層和影片層把同一個頻道歸到不同單位。
-- 2. 頻道名稱相同：YouTube 上改名後（例如 2026-11 Taiwan Explained by TaiwanPlus → TaiwanPlus Explains），
--    metadata 會跟著變，這個測試會在每日檢查失敗，提醒更新 seed 的 channel_name
--    （channel_name 是 chatbox 篩單一頻道用的值，也出現在 agent 說明裡）。
select distinct
  b.channel_id,
  b.dept_scope           as broad_dept_scope,
  c.dept_scope           as seed_dept_scope,
  b.channel_display_name as youtube_channel_name,
  c.channel_name         as seed_channel_name
from {{ source('youtube', 'video_news_broad') }} b
left join {{ ref('youtube_channels') }} c using (channel_id)
where c.dept_scope is distinct from b.dept_scope
   or c.channel_name is distinct from b.channel_display_name
