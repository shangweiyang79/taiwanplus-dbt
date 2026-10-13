# taiwanplus_dbt

TaiwanPlus 新聞部社群成效的 dbt 轉換層（BigQuery `ivory-airfoil-418408`，asia-east1）。

- **範圍**：新聞部 = Newsroom + Talks + Connected，平台為 YouTube / Instagram / Facebook / X。
- **分工**：資料的抓取與寫入（E/L）仍由 `../TaiwanPlus_api` 和 `../news_classification_project` 的 Python 腳本與 Cloud Run 負責；本專案只做轉換、測試與指標定義。兩邊之間的合約是 BigQuery 原表，宣告在 `models/staging/_sources.yml`。
- **環境**：
  - `dev` 寫進 `dbt_joy`。
  - `prod`（切換後）寫回 `social_hub`，並沿用原本的 view 名稱，Looker Studio 不用重接。

## 使用

```powershell
gcloud auth application-default login   # 第一次
dbt debug
dbt build                               # 每週 Python 腳本跑完之後執行
```

profile 放在 `~/.dbt/profiles.yml`，不進版控。

## 結構

| 位置 | 內容 |
|---|---|
| `models/staging/` | 各平台原表統一欄位，加上 `dept_scope` |
| `models/intermediate/` | 四平台疊成長表、post_map 去重 |
| `models/marts/agg_news_dept_daily_traffic_monthly`、`fct_daily_traffic` | **每日流量**（當期實際發生的觀看），**總體成效 KPI** 用這層 |
| `models/marts/fct_social_post_performance`、`agg_news_dept_social_monthly` | **影片層**（依發布日累計），原因分析 / 找表現好的影片用這層 |
| `models/social_hub/` | 與舊 `social_hub` view 同名的相容層（只有 Newsroom），給 Looker Studio |
| `models/docs/_definitions.md` | 「新聞部」「影片觀看」等定義，**改定義只改這裡** |
| `seeds/dept_accounts.csv` | 單位 × 平台 × 原表對照 |
| `seeds/youtube_channels.csv` | YouTube 頻道 → 單位對照（每日流量層用） |
| `seeds/platform_metric_glossary.csv` | 各平台指標的原生欄位與名稱對照 |
| `tests/` | walkthrough §3.6 的哨兵檢查 |
| `scripts/reconcile_social_hub.py` | 逐列對帳 dbt 版與舊版 13 張 `social_hub` view（`python scripts/reconcile_social_hub.py --new <dataset> --old <dataset>`） |

## Semantic layer

- 總體成效 KPI 是每日流量的 `traffic_views`；影片層的 `video_views` 用於原因分析。預設範圍是新聞部三個單位。
- 預設問題對應的 saved query：
  - `news_dept_social_performance`：新聞部社群成效
  - `newsroom_social_performance`：只看 Newsroom
- 其他 metric：各平台的 `*_video_views`、`watch_time_hours`、`engagements`、`engagement_rate`、`post_count`、`avg_views_per_post`、`impressions`（僅 YouTube）。

本機的 `dbt sl validate` / `dbt sl query` 需要 dbt platform（`dbt_cloud.yml`）。

## AI chatbot（免費路線）

| 檔案 | 用途 |
|---|---|
| `models/marts/agg_news_dept_social_monthly` | 認證匯總表（月 × 單位 × 平台），常見問題直接讀這張 |
| `ai_context/news_dept_social_context.md` | 給 AI 讀的定義檔，**自動產生，不要手改** |
| `ai_context/eval_questions.yml` | 7 題測試題庫，用來檢驗 chatbot 的回答 |
| `ai_context/claude_skill/SKILL.md` | Claude Code skill 的版控副本。實際生效的位置是 `analytics_pipeline/.claude/skills/news-dept-social/` |

改了定義（`_definitions.md`、`_marts.yml`、seeds）之後：

```powershell
dbt build --target prod                     # 部署
python scripts/build_ai_context.py          # 重新產生 AI 定義檔
python scripts/run_eval_reference.py        # 看測試題庫的標準答案
```沒有的話，可以改用 `dbt-semantic-interfaces` 驗證 `target/semantic_manifest.json`。
