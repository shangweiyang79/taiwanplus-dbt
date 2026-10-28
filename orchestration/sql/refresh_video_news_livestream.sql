-- Newsroom YouTube 影片表（每支影片一列，累計指標）：TaiwanPlus News / Livestream / Explained。
-- 與 refresh_video_news_broad 的 dept_scope = 'newsroom' 應一致。
-- 原本是 BQ 排程查詢 `yt_video_news_livestream`（台北時間固定時間執行），2026-10 起改由
-- Workflow youtube-owner-chain 在 owner transfer 寫入新資料後呼叫，見 orchestration/README.md。
-- 專案不寫死：沒指定專案的 dataset.table 會解析到 procedure 所在的專案。
CREATE OR REPLACE PROCEDURE `youtube_channel_summary.refresh_video_news_livestream`()
BEGIN
  CREATE OR REPLACE TABLE `youtube_channel_summary.video_news_livestream`

    PARTITION BY DATE(time_published)

  AS

  -- 1. 聚合基礎指標 (Views, Watch Time 等)

  WITH

    daily_stats AS (

      SELECT

        video_id,

        date,

        SUM(views) AS views,

        SUM(engaged_views) AS engaged_views,

        SUM(watch_time_minutes) AS watch_time_minutes,

        SUM(subscribers_gained) AS subscribers_gained,

        SUM(subscribers_lost) AS subscribers_lost,

        SUM(likes) AS likes,

        SUM(comments) AS comments,

        SUM(shares) AS shares

      FROM

        `youtube_taiwanplus_owner.p_content_owner_basic_a4_owner`

      GROUP BY 1, 2

    ),

    -- 2. 聚合曝光指標

    daily_reach AS (

      SELECT

        video_id,

        date,

        SUM(video_thumbnail_impressions) AS daily_impressions,

        SAFE_DIVIDE(

          SUM(video_thumbnail_impressions * video_thumbnail_impressions_ctr),

          SUM(video_thumbnail_impressions))

          AS daily_ctr

      FROM

        `youtube_taiwanplus_owner.p_content_owner_reach_basic_a1_owner`

      GROUP BY 1, 2

    )

  -- 3. 主查詢：將預聚合的 CTE 與 metadata 連接

  SELECT

    meta.channel_display_name,

    meta.video_title,

    stats.video_id,

    meta.video_url,

    PARSE_TIMESTAMP('%Y/%m/%d %H:%M:%S', meta.time_published) AS time_published,

    meta.video_length,

    SUM(stats.views) AS total_views,

    SUM(stats.engaged_views) AS total_engaged_views,

    SUM(stats.watch_time_minutes) / 60 AS total_watch_time_hours,

    -- 修正：使用加權平均計算觀看百分比

    -- 公式：(總觀看分鐘數 * 100) / (總觀看次數 * 影片長度(秒) / 60)

    SAFE_DIVIDE(

      SUM(stats.watch_time_minutes) * 100,

      SUM(stats.engaged_views) * (meta.video_length / 60))

      AS avg_view_duration_percentage,

    SUM(stats.subscribers_gained) - SUM(stats.subscribers_lost)

      AS net_subscribers,

    SUM(stats.likes) AS total_likes,

    SUM(stats.comments) AS total_comments,

    SUM(stats.shares) AS total_shares,

    SUM(reach.daily_impressions) AS total_impressions,

    SAFE_DIVIDE(

      SUM(reach.daily_impressions * reach.daily_ctr),

      SUM(reach.daily_impressions))

      AS total_ctr

  FROM daily_stats AS stats

  INNER JOIN

    `youtube_taiwanplus_owner.p_content_owner_video_metadata_a4_owner`

      AS meta

    ON stats.video_id = meta.video_id

  LEFT JOIN daily_reach AS reach

    ON stats.video_id = reach.video_id AND stats.date = reach.date

  WHERE

    meta.channel_id IN ('UCCJBSLNtozkO-NqjpPZujiQ', 'UC7c6rvyAZLpKGk8ttVnpnLA', 'UComl1gAjeqAAiRR6s3ae73w')

    AND PARSE_TIMESTAMP('%Y/%m/%d %H:%M:%S', meta.time_published) >= '2026-01-01'

    AND meta._PARTITIONDATE = (

      SELECT MAX(_PARTITIONDATE)

      FROM

        `youtube_taiwanplus_owner.p_content_owner_video_metadata_a4_owner`

    )

  GROUP BY 1, 2, 3, 4, 5, 6;
END;
