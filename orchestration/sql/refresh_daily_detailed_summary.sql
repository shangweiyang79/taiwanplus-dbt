-- YouTube 各頻道每日流量（channel × date），MERGE 最近 14 天。
-- 來源：youtube_taiwanplus_owner.p_content_owner_traffic_source_a3_owner
-- 原本是 BQ 排程查詢 `daily_youtube_sum_update`（台北時間固定時間執行），2026-10 起改由
-- Workflow youtube-owner-chain 在 owner transfer 寫入新資料後呼叫，見 orchestration/README.md。
-- 專案不寫死：沒指定專案的 dataset.table 會解析到 procedure 所在的專案。
CREATE OR REPLACE PROCEDURE `youtube_channel_summary.refresh_daily_detailed_summary`()
BEGIN
  MERGE `youtube_channel_summary.daily_detailed_summary` T  -- T 是你的目標表

  USING (

    -- 這部分是你的來源 Query，只抓最近 14 天

    SELECT 

      channel_id, 

      date, 

      SUM(views) AS total_views, 

      SUM(watch_time_minutes)/60 AS total_watch_hours, 

      SUM(CASE WHEN traffic_source_type = 1 THEN views ELSE 0 END) AS paid_views, 

      SUM(CASE WHEN traffic_source_type = 1 THEN watch_time_minutes ELSE 0 END)/60 AS paid_watch_hours, 

      (SUM(views)- SUM(CASE WHEN traffic_source_type = 1 THEN views ELSE 0 END)) AS original_views, 

      (SUM(watch_time_minutes)- SUM(CASE WHEN traffic_source_type = 1 THEN watch_time_minutes ELSE 0 END))/60 AS original_watch_hours, 

      SUM(CASE WHEN country_code = 'TW' THEN views ELSE 0 END) AS taiwan_views 

    FROM 

      `youtube_taiwanplus_owner.p_content_owner_traffic_source_a3_owner` 

    WHERE 

      _PARTITIONTIME >= TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))

    GROUP BY 

      channel_id, 

      date

  ) S  -- S 是來源數據 (Source)

  ON T.channel_id = S.channel_id AND T.date = S.date  -- 比對條件



  -- 1. 如果資料已存在，就更新數值

  WHEN MATCHED THEN

    UPDATE SET

      T.total_views = S.total_views,

      T.total_watch_hours = S.total_watch_hours,

      T.paid_views = S.paid_views,

      T.paid_watch_hours = S.paid_watch_hours,

      T.original_views = S.original_views,

      T.original_watch_hours = S.original_watch_hours,

      T.taiwan_views = S.taiwan_views



  -- 2. 如果是新資料，就插入

  WHEN NOT MATCHED THEN

    INSERT (channel_id, date, total_views, total_watch_hours, paid_views, paid_watch_hours, original_views, original_watch_hours, taiwan_views)

    VALUES (S.channel_id, S.date, S.total_views, S.total_watch_hours, S.paid_views, S.paid_watch_hours, S.original_views, S.original_watch_hours, S.taiwan_views);
END;
