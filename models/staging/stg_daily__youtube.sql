-- 一列 = 日 × 新聞部單位，YouTube 每日流量（當天實際發生的觀看，不分影片發布日）。
-- 頻道 → 單位的對照在 seed youtube_channels（新聞部 5 個頻道）。
-- views 含付費觀看（paid_views 另列）。
-- engaged_views 從 owner 報表的影片 × 日加總到頻道 × 日；2026-09 實測兩邊的 views 差距 < 0.5%，口徑一致。
with daily as (
  select
    parse_date('%Y%m%d', d.date)                    as date,
    c.dept_scope,
    sum(d.total_views)                              as views,
    sum(d.paid_views)                               as paid_views,
    sum(d.total_watch_hours)                        as watch_time_hours
  from {{ source('youtube', 'daily_detailed_summary') }} d
  join {{ ref('youtube_channels') }} c
    on d.channel_id = c.channel_id
  group by 1, 2
),
video_channel as (
  select distinct video_id, channel_id
  from {{ source('youtube_owner', 'p_content_owner_video_metadata_a4_owner') }}
  where _partitiondate = (
    select max(_partitiondate)
    from {{ source('youtube_owner', 'p_content_owner_video_metadata_a4_owner') }}
  )
),
engaged as (
  select
    parse_date('%Y%m%d', b.date)                    as date,
    c.dept_scope,
    sum(b.engaged_views)                            as engaged_views
  from {{ source('youtube_owner', 'p_content_owner_basic_a4_owner') }} b
  join video_channel v using (video_id)
  join {{ ref('youtube_channels') }} c
    on v.channel_id = c.channel_id
  group by 1, 2
)
select
  d.date,
  d.dept_scope,
  'YouTube'                                         as platform,
  'video'                                           as content_type,
  d.views,
  d.paid_views,
  e.engaged_views,
  d.watch_time_hours,
  'youtube_analytics'                               as source_method
from daily d
left join engaged e
  on d.date = e.date and d.dept_scope = e.dept_scope
