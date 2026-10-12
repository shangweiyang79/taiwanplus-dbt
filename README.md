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
