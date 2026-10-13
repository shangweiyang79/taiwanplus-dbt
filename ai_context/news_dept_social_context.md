# TaiwanPlus 新聞部社群成效：AI 查詢說明

> 由 `taiwanplus_dbt/scripts/build_ai_context.py` 自動產生（2026-10-13），**不要手改**。
> 定義的來源是 dbt 專案：`models/docs/_definitions.md`、`models/marts/_marts.yml`、`seeds/`。
> 資料庫是 BigQuery（專案 `ivory-airfoil-418408`，位置 asia-east1），SQL 一律用 GoogleSQL。

## 1. 業務定義

### 新聞部

**新聞部（News Department）= Newsroom + Talks + Connected 三個單位。**

- 問「新聞部」的社群成效時，三個單位都要算；只有明確說 Newsroom（新聞台）時才篩 `dept_scope = 'newsroom'`。
- 各單位經營的平台：
  - Newsroom：YouTube（TaiwanPlus News / TaiwanPlus Livestream / Taiwan Explained by TaiwanPlus）、Instagram、Facebook、X
  - Talks：YouTube（Taiwan Talks）、Instagram
  - Connected：YouTube（CONNECTED on TaiwanPlus）；Instagram 於 2026-07-04 停更，歷史資料保留
- 單位、平台、原表的完整對照見 seed `dept_accounts`。

### 每日流量與影片層（兩種觀看數）

**新聞部的觀看數有兩層，口徑不同、數字不同，不能混用：**

| | 每日流量（daily traffic） | 影片層（video level） |
|---|---|---|
| 意思 | 該期間內**實際發生**的觀看，不管影片何時發布 | 該期間**發布**的影片，到今天為止的**累計**觀看 |
| 用途 | **總體成效（KPI）**：某月 / 某期間總共多少觀看、整體趨勢 | **原因分析**：哪些影片 / 主題 / 節目表現好、為什麼 |
| 表 | `agg_news_dept_daily_traffic_monthly`、`fct_daily_traffic` | `agg_news_dept_social_monthly`、`fct_social_post_performance` |
| 指標 | `traffic_views` | `video_views` |

例（2026-09 實測）：YouTube Newsroom 的每日流量約為影片層的 1.5 倍；IG Talks 則相反，影片層約為每日流量的 2 倍。

每日流量的資料限制：
- 起始日：YouTube 2025-06-28、FB 2025-08-01、IG 2025-08-01、IG Stories 2025-09-14、X 2025-12-29。更早的期間沒有每日流量。
- **IG 於 2026-06-01 換算法**：之前是每支 reel 的 Total Plays 累計快照逐支相減（`source_method = reel_snapshot_delta`），和之後的官方 API 相比通常偏高 10～20%；跨 6/1 比較 IG 趨勢時要說明。
- IG 觀看時數所有期間都是逐支 reel 快照相減，已排除 API 漏抓 / 回傳 0 造成的負數（例如 2026-07 原報表出現大幅負數的觀看時數）。
- IG 的 views 含影片類 Stories（`story_views` 另列）；YouTube / FB 含付費觀看（`paid_views` 另列）。
- Connected 的 IG 停更後，舊貼文每天仍有觀看，所以每日流量不會是 0（影片層的新發布則是 0）。
- TaiwanPlus Livestream 頻道的每日流量到 2026-08-05 為止。

### 各平台觀看的計算門檻

**影片觀看數，是「社群成效」的預設主指標。**

各平台的原生指標名稱與計算門檻不同，這裡統一叫 `video_views`：

| 平台 | 原生欄位 | 平台上的名稱 | 計算門檻 |
|---|---|---|---|
| YouTube | total_views | Views | **2026-08-27 起播放約 1 秒即計一次；之前約 30 秒**（舊標準約等於現在的 Engaged views） |
| Instagram | Total Plays | Plays | 播放約 0.3～0.5 秒即計（取最新一天的累計快照） |
| Facebook | video_views_3s | 3-second video views | 播放滿 3 秒，**目前四個平台中門檻最嚴格** |
| X | total_video_views | Video views | 連續播放 2 秒 |

YouTube 另有 `engaged_views`（Engaged views），計算方式接近 8/27 之前的舊 Views，作為**輔助參考**。**KPI 仍是 Views**。

解讀規則：
1. **不能跨平台比較優劣**。各平台的計算門檻不同、受眾結構也不同，絕對值不能直接比較。跨平台加總只能看整體量級。
   - **FB 的數字最大，不是因為門檻低**（FB 的 3 秒其實比 IG、X、現在的 YouTube 都嚴格），而是因為 FB 的觀眾群以**菲律賓**最多，和菲律賓有關的新聞在 FB 表現最好。
   - 實測：2026 年 Newsroom 在 FB 上，標題提到菲律賓的貼文平均觀看是其他貼文的 7.8 倍；這些貼文只占貼文數 1.7%，卻貢獻 FB 總觀看的 12%。
2. **要比較時，看同一平台自己的逐月趨勢**。
3. **YouTube 的 Views 於 2026-08-27 放寬門檻**。KPI 仍以 Views 為準，但期間跨過 8/27 時要說明影響：
   - 實測 8/27 之前 Views 約為 Engaged views 的 1.1～1.3 倍，8/27 起變成 2.1～2.7 倍，所以 8/27 之後 Views 的成長有相當部分來自定義放寬。
   - 同時列出 Engaged views 作為輔助參考，幫助判斷實際的觀看變化。
4. **數字都是累計值**，愈晚發布的影片累計天數愈少，最新月份天生偏低，不代表成效衰退。
5. 對照表也存在 seed `platform_metric_glossary`。

## 2. 回答流程

### 判斷範圍

| 使用者說 | 範圍 |
|---|---|
| 新聞部、新聞部門、news department | `dept_scope` in ('newsroom', 'talks', 'connected')，三個都要 |
| Newsroom、新聞台、TaiwanPlus News | `dept_scope = 'newsroom'` |
| Talks、Taiwan Talks | `dept_scope = 'talks'` |
| Connected、CONNECTED | `dept_scope = 'connected'` |
| 沒指定平台 | 該範圍內所有平台（新聞部 = YouTube、Instagram、Facebook、X） |

### 判斷指標

- 「成效」「表現」「performance」「總共多少觀看」沒指定指標時 → **每日流量的 `traffic_views`**（總體成效 KPI）。
- 「為什麼」「原因」「哪些影片 / 主題 / 節目表現好」→ 影片層的 `video_views`，並附上 `post_count`。
- 「互動」→ `engagements`；「互動率」→ `engagement_rate`；「觀看時長」→ `watch_time_hours`（X 沒有）。
- 各平台的觀看指標原生名稱不同（YouTube Views、IG Plays、FB 3-second video views、X Video views），回答時要用統一名稱「影片觀看數」，必要時括號註明原生名稱。
- **YouTube 一律以 Views 為主（KPI）**，同時附上 engaged views（每日流量 `traffic_engaged_views`、影片層 `yt_engaged_views`）作為輔助參考。期間跨過 2026-08-27 時（例如比較 7 月與 9 月），要說明 Views 的變化有一部分來自門檻放寬。

### 判斷期間

- 「近期」「最近」沒指定期間時 → **最近三個完整月份**；若也列出本月，必須標註「本月至今、尚未完整」。
- 每日流量的期間依**觀看發生日**（`date`）；影片層的期間依**影片發布日**（`publish_date`）。

### 選擇資料表

| 問題類型 | 查哪張 |
|---|---|
| **總體成效**：新聞部 / 單位 / 平台的逐月成效、趨勢、某月總共多少觀看（最常見） | `news_dept_social.agg_news_dept_daily_traffic_monthly`，**直接讀，不要自己從明細加總** |
| 總體成效，但期間是自訂的（某幾週、某幾天） | `news_dept_social.fct_daily_traffic` |
| **原因分析**：哪些影片表現最好、依主題 / 節目 / 直式切分、單則貼文排行 | `news_dept_social.fct_social_post_performance` |
| 原因分析的逐月彙總（依發布月份） | `news_dept_social.agg_news_dept_social_monthly` |

**問「為什麼」時兩層都要用**：先用每日流量說明總體變化，再用影片層找出貢獻最大的影片 / 主題，並說明兩層口徑不同（影片層是依發布日累計）。
| 單位、平台、帳號對照，某帳號是否停更 | `news_dept_social.dept_accounts` |
| 指標在各平台的原生欄位與定義 | `news_dept_social.platform_metric_glossary` |

不要查 `dbt_internal` 或各平台原表：原表有快照、重複等陷阱（例如 IG 原表直接 SUM 會灌水上百倍），已在上述表格處理好。

### 呈現規則

1. **各平台分開列**。不要把四個平台的觀看數加總成單一數字當主結論；若列出總和，要註明「各平台定義不同，只能看量級」。
2. **不要用絕對值比較平台優劣**。比較請看各平台自己的逐月趨勢（例如月增率）。
   - 解釋 FB 數字為什麼最大時，原因是**菲律賓受眾**，不是「門檻低」（FB 的 3 秒門檻是四個平台中最嚴格的）。
3. **YouTube 以 Views 為主、Engaged views 為輔**。期間跨過 2026-08-27 時，Views 的成長不能全部歸因於成效，要搭配 Engaged views 說明有多少來自定義放寬。
4. 影片層的最新月份累計天數少、天生偏低，不要解讀成衰退；每日流量的本月則是天數未滿（看 `days_with_data`）。
5. 主動說明資料限制：
   - Connected 的 IG 於 2026-07-04 停更
   - Talks / Connected 沒有主題分類
   - X 沒有觀看時長
   - YouTube Views 定義於 2026-08-27 變更；影片層 YouTube 資料從 2026-01-01 起
   - IG 每日流量於 2026-06-01 換算法（之前偏高 10～20%）
   - 每日流量各平台的起始日不同（見 §1），更早的期間沒有每日流量
6. 平均值易被少數爆量貼文拉高，引用平均時一併看 `max_views_per_post`。
7. **回答時寫明用的是哪一層**（「每日流量」或「影片層」），兩層的數字不要放在同一欄比較。

## 3. 資料表

### `ivory-airfoil-418408.news_dept_social.agg_news_dept_daily_traffic_monthly`

一列 = 月 × 新聞部單位 × 平台，新聞部「總體成效」的認證匯總表（每日流量）。 問總體成效、趨勢、某月總共多少觀看時直接讀這張，不要自己從明細加總。 **新聞部（News Department）= Newsroom + Talks + Connected 三個單位。**

| 欄位 | 說明 |
|---|---|
| `month_start` | 月份第一天（依觀看發生日）。 |
| `year_month` | 月份字串（YYYY-MM）。 |
| `dept_scope` | 新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。 |
| `platform` | 社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。 |
| `views` | 影片觀看數，各平台定義不同（見 §1）。 |
| `video_views_only` | 不含 Stories 的觀看數。 |
| `story_views` | IG 影片類 Stories 的觀看數（只有 IG 有）。 |
| `engaged_views` | YouTube 的 Engaged views（輔助參考）。KPI 仍是 views；跨 2026-08-27 比較時一併列出。 |
| `paid_views` | 付費觀看，已包含在 views 裡。 |
| `watch_time_hours` | 當月觀看時數。 |
| `days_with_data` | 當月有資料的天數。少於當月天數代表資料不完整（例如本月、或資料起始月）。 |
| `source_method` | 資料算法。IG 出現 reel_snapshot_delta 代表 2026-06 之前的快照算法，通常比 API 偏高 10～20%。 |
| `is_current_month` | 是否為本月（台北時間），本月資料不完整。 |

### `ivory-airfoil-418408.news_dept_social.fct_daily_traffic`

一列 = 日 × 新聞部單位 × 平台 × 內容類型（video / story），新聞部每日流量的主表。

| 欄位 | 說明 |
|---|---|
| `traffic_uid` | 唯一鍵，格式為 `日期:單位:平台:內容類型`。 |
| `date` | 觀看發生的日期（不是影片發布日）。 |
| `year_month` | 月份字串（YYYY-MM）。 |
| `month_start` | 月份第一天。 |
| `dept_scope` | 新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。 |
| `platform` | 社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。 |
| `content_type` | 內容類型：`video`（影片 / reels）或 `story`（IG 影片類 Stories）。 |
| `views` | 影片觀看數，各平台定義不同（見 §1）。 |
| `paid_views` | 付費觀看（YouTube、FB、IG 有欄位；X 為 NULL）。 |
| `engaged_views` | YouTube 的 Engaged views（輔助參考，其他平台為 NULL）。KPI 仍是 views。 |
| `watch_time_hours` | 當天的觀看時數。IG 為逐支 reel 快照相減（已排除 API 漏抓造成的負數）；FB 由分鐘換算；Stories 為 NULL。 |
| `source_method` | 資料算法：youtube_analytics / facebook_insights / x_analytics / api（IG 2026-06-01 起）/ reel_snapshot_delta（IG 2026-06-01 前，逐支 reel 快照相減）/ story_by_publish_date（IG Stories）。 |

### `ivory-airfoil-418408.news_dept_social.agg_news_dept_social_monthly`

一列 = 月 × 新聞部單位 × 平台，新聞部社群成效的認證匯總表。 常見問題（新聞部 / 各單位 / 各平台的逐月成效）直接查這張，不要從明細自己加總。 **新聞部（News Department）= Newsroom + Talks + Connected 三個單位。**

| 欄位 | 說明 |
|---|---|
| `month_start` | 月份第一天（依各平台發布日）。 |
| `year_month` | 月份字串（YYYY-MM）。 |
| `dept_scope` | 新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。 |
| `platform` | 社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。 |
| `video_views` | 影片觀看數，各平台計算門檻不同（見表格說明），不可跨平台比較優劣。YouTube 於 2026-08-27 放寬門檻。 |
| `engaged_views` | YouTube 的 Engaged views（輔助參考，其他平台為 NULL）。KPI 仍是 video_views；跨 2026-08-27 比較時一併列出。 |
| `post_count` | 影片貼文數。 |
| `watch_time_hours` | 觀看時長（小時）。X 沒有，為 NULL。 |
| `engagements` | 互動數，各平台定義見 fct_social_post_performance.engagements。 |
| `engagement_rate` | 互動數 / 影片觀看數。只能在同一平台內比較。 |
| `avg_views_per_post` | 平均每則觀看數。易受少數爆量貼文影響，請搭配 max_views_per_post 判讀。 |
| `max_views_per_post` | 單則最高觀看數，用來判斷平均值是否被爆量貼文拉高。 |
| `is_current_month` | 是否為本月（台北時間）。本月資料不完整，數字天生偏低。 |
| `days_since_month_end` | 該月最後一天距今幾天。負數 = 本月尚未結束；數字愈小，累計愈不完整。 |

### `ivory-airfoil-418408.news_dept_social.fct_social_post_performance`

一列 = 新聞部（Newsroom + Talks + Connected）在任一平台上的一則影片貼文，是新聞部社群成效的主表。

| 欄位 | 說明 |
|---|---|
| `post_uid` | 貼文唯一鍵，格式為 `平台:貼文 ID`。 |
| `vod_id` | CMS 的 VOD ID。只有 Newsroom 且走過 CMS 發布流程的貼文才有，其餘為 NULL。 |
| `platform` | 社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。 |
| `dept_scope` | 新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。 |
| `post_key` | 平台上的貼文 ID（YouTube video_id、IG shortcode、FB video_id、X post_id）。 |
| `link` | 貼文連結，取自各平台原表。 |
| `publish_date` | 貼文在該平台的發布日（不是 VOD 的 publish_date）。semantic layer 的預設時間維度。 |
| `year_month` | 發布月份字串（YYYY-MM）。 |
| `month_start` | 發布月份第一天，給 Looker Studio 的日期控制項使用。 |
| `platform_title` | 平台上的標題。YouTube、FB、X 有值；IG 為 NULL。 |
| `caption` | 貼文文案。IG 只有 Newsroom 在 2025-06-02 之後有值；YouTube 為 NULL。 |
| `thumbnail_url` | 縮圖網址。IG、FB 是會過期的 Meta CDN 簽章網址。 |
| `views` | 影片觀看數，各平台定義不同（見 §1）。 |
| `engaged_views` | YouTube 的 Engaged views（輔助參考），其他平台為 NULL。計算方式接近 2026-08-27 之前的舊 Views。 KPI 仍是 views；跨 8/27 比較時一併列出這欄，說明 views 的變化有多少來自定義放寬。 |
| `watch_time_hours` | 觀看時長（小時）。X 不提供，為 NULL。 |
| `engagements` | 互動數。YouTube = 讚 + 留言 + 分享；IG = Reels interactions + Shares；FB = 原生 engagements；X = 讚 + 回覆 + 轉推。 |
| `impressions` | 曝光次數，只有 YouTube 有。 |
| `ctr` | 縮圖點閱率，只有 YouTube 有。 |
| `orientation` | 平台自己的影片形式（shorts / reels / video）。X 的 'video' 代表「無此資訊」，不代表橫式。 |
| `is_vertical` | 是否為直式影片（跨平台正規化）。X 一律為 FALSE（無此資訊），比較直式成效時應排除 X。 |
| `is_in_post_map` | 這則貼文是否走過 CMS 發布流程（有 VOD ID）。 |
| `program` | 節目名稱（只有 Newsroom 的 VOD 有）。 |
| `content_category` | CMS 的內容分類（只有 Newsroom 的 VOD 有）。 |
| `new_category` | 主題分類（9 大類，雲端分類 pipeline 產出，只有 Newsroom 的 VOD 有）。 |
| `tags_text` | 正規化後的 tag，以逗號串接。 |

### `ivory-airfoil-418408.news_dept_social.dept_accounts`

新聞部單位 × 平台 × 原表對照。**新聞部（News Department）= Newsroom + Talks + Connected 三個單位。**

| 欄位 | 說明 |
|---|---|
| `dept_scope` | 新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。 |
| `platform` | 社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。 |
| `account_label` | 帳號 / 頻道名稱。 |
| `source_table` | 該帳號成效資料所在的 BigQuery 原表。 |
| `active_to` | 停更日期。NULL 表示仍在經營。 |
| `note` | 備註。 |

### `ivory-airfoil-418408.news_dept_social.platform_metric_glossary`

各平台指標對照表：統一指標名稱（canonical_metric）對應到各平台的原生欄位與平台上的名稱。 **影片觀看數，是「社群成效」的預設主指標。**

| 欄位 | 說明 |
|---|---|
| `platform` | 社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。 |
| `canonical_metric` | dbt / semantic layer 裡的統一指標名稱。 |
| `native_column` | 平台原表的欄位或計算式。 |
| `native_label` | 平台後台上顯示的名稱。 |
| `definition` | 指標定義。 |
| `cross_platform_comparable` | 能否直接跨平台比較絕對值。 |
| `note` | 備註。 |

### `ivory-airfoil-418408.news_dept_social.youtube_channels`

新聞部 YouTube 頻道 → 單位對照，每日流量層用它把頻道歸到 newsroom / talks / connected。

| 欄位 | 說明 |
|---|---|
| `channel_id` | YouTube 頻道 ID。 |
| `channel_name` | 頻道名稱。 |
| `dept_scope` | 新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。 |
| `note` | 備註。 |

## 4. 指標與對應 SQL

每個指標都是對「所屬表」的聚合。逐月結果已分別算好在 `agg_news_dept_daily_traffic_monthly`（每日流量）與 `agg_news_dept_social_monthly`（影片層）。

| 指標 | 名稱 | 所屬表 | SQL | 說明 |
|---|---|---|---|---|
| `traffic_engaged_views` | 每日流量 Engaged views（YouTube） | `fct_daily_traffic` | `SUM(engaged_views)` | YouTube 每天的 Engaged views，輔助參考用（KPI 仍是 traffic_views）。 |
| `traffic_paid_views` | 每日流量付費觀看 | `fct_daily_traffic` | `SUM(paid_views)` | 付費觀看，已包含在 traffic_views 裡。 |
| `traffic_story_views` | IG Stories 觀看數 | `fct_daily_traffic` | `SUM(IF(content_type = 'story', views, NULL))` | IG 影片類 Stories 的觀看，已包含在 traffic_views 裡。 |
| `traffic_views` | 每日流量觀看數（總體成效 KPI） | `fct_daily_traffic` | `SUM(views)` | 兩層差異見 §1 |
| `traffic_watch_time_hours` | 每日流量觀看時數 | `fct_daily_traffic` | `SUM(watch_time_hours)` | 當天的觀看時數加總（Stories 不含）。 |
| `avg_views_per_post` | 平均每則觀看數 | `fct_social_post_performance` | `SAFE_DIVIDE(SUM(views), COUNT(post_uid))` | 影片觀看數 / 影片貼文數。少數爆量貼文會把平均拉高，建議同時看中位數或最大值。 |
| `engagement_rate` | 互動率 | `fct_social_post_performance` | `SAFE_DIVIDE(SUM(engagements), SUM(views))` | 互動數 / 影片觀看數。各平台觀看與互動定義都不同，只能在同一平台內比較。 |
| `engagements` | 互動數 | `fct_social_post_performance` | `SUM(engagements)` | 互動數加總，各平台定義見 engagements 欄位說明。 |
| `fb_video_views` | Facebook 3 秒觀看數 | `fct_social_post_performance` | `SUM(IF(platform = 'Facebook', views, NULL))` | Facebook 的 3-second video views（video_views_3s），播放滿 3 秒才計，是四個平台中門檻最嚴格的。 FB 數字大是因為受眾以菲律賓為主、菲律賓相關新聞表現特別好，不是門檻低。 |
| `ig_video_views` | Instagram 播放數 | `fct_social_post_performance` | `SUM(IF(platform = 'Instagram', views, NULL))` | Instagram 的 Plays（Total Plays，取最新快照）。 |
| `impressions` | 曝光數（僅 YouTube） | `fct_social_post_performance` | `SUM(impressions)` | 縮圖曝光次數，只有 YouTube 有，不是跨平台指標。 |
| `post_count` | 影片貼文數 | `fct_social_post_performance` | `COUNT(post_uid)` | 影片貼文數。 |
| `video_views` | 影片層觀看數（依發布日累計） | `fct_social_post_performance` | `SUM(views)` | 影片層：該期間「發布」的影片，到今天為止的累計觀看。用於影片 / 主題 / 節目 / 原因分析， 不用於總體成效（總體成效用 traffic_views）。各平台門檻見 platform_metric_glossary。 |
| `watch_time_hours` | 觀看時長（小時） | `fct_social_post_performance` | `SUM(watch_time_hours)` | 觀看時長加總。X 不提供，所以跨平台加總只含 YouTube + IG + FB。 |
| `x_video_views` | X 影片觀看數 | `fct_social_post_performance` | `SUM(IF(platform = 'X', views, NULL))` | X 的 Video views（total_video_views）。 |
| `yt_engaged_views` | YouTube Engaged views | `fct_social_post_performance` | `SUM(IF(platform = 'YouTube', engaged_views, NULL))` | YouTube 的 Engaged views，計算方式接近 2026-08-27 之前的舊 Views。 輔助參考用，KPI 仍是 yt_video_views；期間跨過 8/27 時一併列出，說明 Views 的變化有多少來自定義放寬。 |
| `yt_video_views` | YouTube 觀看數 | `fct_social_post_performance` | `SUM(IF(platform = 'YouTube', views, NULL))` | YouTube 的 Views（total_views），是 KPI。2026-08-27 起門檻由約 30 秒放寬為約 1 秒， 跨 8/27 比較時另附 yt_engaged_views 參考。 |

## 5. 預設查詢

### 新聞部社群成效（`news_dept_social_performance`）

「新聞部社群成效」的預設答案：新聞部三個單位（Newsroom + Talks + Connected） 在四個平台的每日流量觀看數（當月實際發生的觀看），依月份、單位、平台切分。 各平台觀看門檻不同，請各平台看自己的趨勢，不要跨平台比較優劣。

```sql
SELECT
  DATE_TRUNC(date, MONTH) AS month_start,
  dept_scope,
  platform,
  SUM(views) AS traffic_views,
  SUM(engaged_views) AS traffic_engaged_views
FROM `ivory-airfoil-418408.news_dept_social.fct_daily_traffic`
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

### Newsroom 社群成效（`newsroom_social_performance`）

只看 Newsroom（新聞台）在四個平台的每日流量觀看數，依月份與平台切分。

```sql
SELECT
  DATE_TRUNC(date, MONTH) AS month_start,
  platform,
  SUM(views) AS traffic_views,
  SUM(engaged_views) AS traffic_engaged_views
FROM `ivory-airfoil-418408.news_dept_social.fct_daily_traffic`
WHERE dept_scope = 'newsroom'
GROUP BY 1, 2
ORDER BY 1, 2
```

## 6. 對照表內容

### dept_accounts（單位 × 平台）

| dept_scope | dept_label | platform | account_label | source_table | active_to | note |
|---|---|---|---|---|---|---|
| newsroom | Newsroom | YouTube | TaiwanPlus News / TaiwanPlus Livestream / Taiwan Explained by TaiwanPlus | youtube_channel_summary.video_news_broad |  | 新聞部原本的範圍 |
| newsroom | Newsroom | Instagram | Newsroom IG | Instagram_data.News |  |  |
| newsroom | Newsroom | Facebook | Newsroom FB | Facebook_data.TaiwanPlus_news_videos |  |  |
| newsroom | Newsroom | X | Newsroom X | X_data.post_metrics |  |  |
| talks | Talks | YouTube | Taiwan Talks | youtube_channel_summary.video_news_broad |  |  |
| talks | Talks | Instagram | Talks IG | Instagram_data.Talks |  |  |
| connected | Connected | YouTube | CONNECTED on TaiwanPlus | youtube_channel_summary.video_news_broad |  |  |
| connected | Connected | Instagram | Connected IG | Instagram_data.Connected | 2026-07-04 | 已停更，歷史資料保留；實測最後一則 reel 發布於 2026-07-10 |

### platform_metric_glossary（指標 × 平台）

| platform | canonical_metric | native_column | native_label | definition | cross_platform_comparable | note |
|---|---|---|---|---|---|---|
| YouTube | video_views | total_views | Views | 播放約 1 秒即計（2026-08-27 起；之前約 30 秒） | false | KPI。跨 2026-08-27 比較時另附 engaged_views 參考 |
| YouTube | engaged_views | total_engaged_views | Engaged views | 計算方式接近 2026-08-27 之前的舊 Views | false | 輔助參考，不是 KPI |
| Instagram | video_views | Total Plays | Plays | 播放約 0.3～0.5 秒即計 | false | 原表是每日累計快照，直接 SUM 會灌水上百倍 |
| Facebook | video_views | video_views_3s | 3-second video views | 播放滿 3 秒才計（四個平台中最嚴格） | false | 數字大是因為受眾以菲律賓為主、菲律賓相關新聞表現特別好，不是門檻低 |
| X | video_views | total_video_views | Video views | 連續播放 2 秒才計 | false |  |
| YouTube | watch_time_hours | total_watch_time_hours | Watch time (hours) | 觀看時長（小時） | false |  |
| Instagram | watch_time_hours | View total time_hrs | View total time | 觀看時長（小時） | false |  |
| Facebook | watch_time_hours | hours_viewed |  | 觀看時長（小時） | false |  |
| X | watch_time_hours |  |  | X 不提供觀看時長 | false |  |
| YouTube | engagements | total_likes + total_comments + total_shares |  | 按讚 + 留言 + 分享 | false |  |
| Instagram | engagements | Reels interactions + Shares |  | Reels 互動 + 分享 | false |  |
| Facebook | engagements | engagements | Engagements | FB 原生互動數（心情 + 留言 + 分享） | false |  |
| X | engagements | likes + comments_replies + shares_retweets |  | 按讚 + 回覆 + 轉推 | false | 不用 total_actions（不含留言，會低估約 5%） |

### youtube_channels（YouTube 頻道 × 單位）

| channel_id | channel_name | dept_scope | note |
|---|---|---|---|
| UCCJBSLNtozkO-NqjpPZujiQ | TaiwanPlus News | newsroom |  |
| UC7c6rvyAZLpKGk8ttVnpnLA | TaiwanPlus Livestream | newsroom | 每日流量資料到 2026-08-05 為止，最後一支影片發布於 2026-07-16 |
| UComl1gAjeqAAiRR6s3ae73w | Taiwan Explained by TaiwanPlus | newsroom |  |
| UCSyJ1WvirdmrMY8rpnT41LA | Taiwan Talks | talks |  |
| UC1oUAE7Bj5o6zEGm0Hq4BdA | CONNECTED on TaiwanPlus | connected |  |
