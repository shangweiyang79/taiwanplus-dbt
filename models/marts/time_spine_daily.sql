{{ config(materialized='table') }}

-- 一列 = 一天。給 semantic layer（MetricFlow）做時間彙總用。
-- 涵蓋 IG 最早的資料（2023 年）到未來 30 天。
select date_day
from unnest(generate_date_array(date '2023-01-01', date_add(current_date('Asia/Taipei'), interval 30 day))) as date_day
