{{ config(severity='warn') }}

-- FB 影片分兩張表：歷史表（2024–2025 凍結快照）與原表（2026-01-01 起每天回刷）。
-- 兩張表不該重疊，歷史表也不該有 2026 年的影片。stg_facebook__videos 已排除重疊（以原表為準），
-- 所以只警告不中斷；出現時代表有人用 Cloud Run 的 start 參數把 2025 年的影片寫進原表，或歷史表被重新匯入。
select
  h.video_id,
  h.publish_date,
  case when c.video_id is not null then 'in_current_table' else 'history_after_2025' end as problem
from {{ source('facebook', 'TaiwanPlus_news_videos_history') }} h
left join {{ source('facebook', 'TaiwanPlus_news_videos') }} c using (video_id)
where c.video_id is not null
   or h.publish_date >= date '2026-01-01'
