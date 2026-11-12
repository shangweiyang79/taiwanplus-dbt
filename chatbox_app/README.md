# 新聞部社群成效 Data Chatbox（Cloud Run + IAP）

這是一個網頁 chatbox，讓同事用中文或英文問新聞部（Newsroom + Talks + Connected）的社群成效。

- **後端**：Conversational Analytics API 的 Data Agent `news-dept-social`。agent 的設定與評估在 `../ai_context/ca_agent/`。
- **執行身分**：唯讀 SA `data-chatbox-ro`，只能讀 `news_dept_social`，任何寫入都會被拒（驗證方式見 `../ai_context/ca_agent/verify_readonly.py`）。
- **登入**：IAP 限定授權的 Google 帳號，其他人打不開頁面。

| 資源 | 名稱 |
|---|---|
| 專案 / 區域 | `<gcp-project>` / `asia-east1` |
| Cloud Run 服務 | `data-chatbox` |
| 映像 | `asia-east1-docker.pkg.dev/<gcp-project>/data-chatbox/app:vN` |
| 執行身分 | `data-chatbox-ro@<gcp-project>.iam.gserviceaccount.com` |
| 撰寫模型權限 | 自訂角色 `chatboxGeminiInvoker`，只有 `aiplatform.endpoints.predict`（呼叫 Vertex AI 模型），2026-10-15 經使用者同意授予 SA |

## 回答模式

評估紀錄都在 `../ai_context/ca_agent/eval_results/`。

| 模式 | 流程 | 延遲 | 什麼時候用 |
|---|---|---|---|
| ⚡ 快速 | CA API FAST 取數並回答，`notes.py` 補提醒 | 約 5–20 秒 | 單純查數：多少、列出、前幾名 |
| 🧠 深入分析 | CA API FAST 取數 → `narrator.py` 用 Gemini Flash 串流撰寫分析 | 約 18–25 秒，取完數就開始出字 | 需要判斷：為什麼、是真的嗎、哪個最好、成效如何、比較、趨勢 |

- **「自動」**由 `notes.route_mode` 依關鍵字判斷用哪個模式；側欄可以手動指定。
- **深入分析為什麼不用 CA API 的 THINKING 模式**（2026-10-15 實測）：
  - THINKING 一題約 32–34 秒，其中「撰寫分析」占 20–22 秒，而且資料要等到最後才會送回。
  - 改成「FAST 取數＋`gemini-3.8-flash` 撰寫」後，3 題判斷型問題的品質相當，時間約 18–21 秒。
  - 撰寫規則直接讀已部署 agent 的 system_instruction，不另存一份。
  - 撰寫時偶爾會抄錯數字，所以 `narrator.unmatched_numbers` 會檢查回答裡的數字，查詢結果中找不到的會顯示黃色提醒。
  - 換撰寫模型（`config.NARRATOR_MODEL`）或改 prompt 之後，要跑 `python eval_deep.py` 重新評估。
- **快速模式**取數正確，但回答常漏掉業務提醒。所以 `notes.build_notes` 會依查詢結果，用固定規則補上提醒：YouTube 8/27 門檻、IG 6/1 換算法、Connected IG 停更、跨平台不可比、本月未完整，以及「查詢範圍」。回答裡已經講過的提醒不會重複附上。
- **語言**：中文問題會在訊息後面附上「請用繁體中文回答」，英文問題附上 "Please answer in English."。實測快速模式兩個方向都會出錯：中文問題常用英文回答，英文問題也會用中文回答（2026-11-03 英文 FB 範例題）。

## 介面注意事項

- **介面標籤中英並陳**（2026-11-03 起，有外國同事使用）：標題、側欄、輸入框、狀態列、展開區都是「中文 English」。答案下方的資料提醒、查詢範圍、數字核對提醒，以及側欄底部的資料說明，刻意維持只有中文（使用者決定）。範例問題最後一題是英文。英文問題在深入分析時，`narrator` 會另外要求用英文回答。
- **圖片一律用 data URI**（`app.data_uri`），不要用檔案路徑。Streamlit 1.57 透過 `/media/` 送圖片時，經過 IAP 會回 500（`Expected ASGI message 'http.response.start'`），2026-10-15 logo 就因此沒顯示。
- **CA API 的「建議追問」不顯示**：有些建議的問題，資料表裡根本沒有資料可以回答（2026-10-15 使用者回饋）。
- **圖表來自 CA API**（Vega-Lite），不是撰寫模型畫的。快速取數時 CA API 常會附上趨勢圖。

## 本機執行

```bash
cd taiwanplus_dbt/chatbox_app
pip install -r requirements.txt
export GCP_PROJECT=<gcp-project>   # 專案 ID 不寫進程式碼（repo 是公開的）；Cloud Run 上沒設時自動用服務所在的專案
python test_notes.py
streamlit run app.py      # 本機會模擬 data-chatbox-ro，你需要在 SA 上有 serviceAccountTokenCreator
```

## 部署 / 更新

gcloud 預設專案不是 ivory 時，每個指令都要加 `--project=<gcp-project> --billing-project=<gcp-project>`。

```bash
# 0.（只有第一次）啟用 API、建 Artifact Registry、建立 IAP service agent
gcloud services enable iap.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com
gcloud artifacts repositories create data-chatbox --repository-format=docker --location=asia-east1
gcloud beta services identity create --service=iap.googleapis.com

# gcloud 預設的計費專案若不是本專案（會出現 Cloud Build API SERVICE_DISABLED），以下指令都加 --billing-project=<gcp-project>
# 1. 建映像（先查目前的 tag，用下一號，不要覆寫舊號碼）
gcloud run services describe data-chatbox --region=asia-east1 --format="value(spec.template.spec.containers[0].image)"
gcloud builds submit --tag asia-east1-docker.pkg.dev/<gcp-project>/data-chatbox/app:vN

# 2. 部署（IAP 直接掛在 Cloud Run 上，不需要 Load Balancer）
gcloud run deploy data-chatbox --region=asia-east1 \
    --image=asia-east1-docker.pkg.dev/<gcp-project>/data-chatbox/app:vN \
    --service-account=data-chatbox-ro@<gcp-project>.iam.gserviceaccount.com \
    --no-allow-unauthenticated --iap \
    --session-affinity --timeout=3600 \
    --cpu=1 --memory=1Gi --min-instances=0 --max-instances=2 --concurrency=20

# 3.（只有第一次）讓 IAP 能呼叫服務
gcloud run services add-iam-policy-binding data-chatbox --region=asia-east1 \
    --member=serviceAccount:service-<project-number>@gcp-sa-iap.iam.gserviceaccount.com \
    --role=roles/run.invoker
```

- `--session-affinity`：Streamlit 用 WebSocket 維持對話狀態，同一位使用者要固定連到同一個執行個體。
- `--min-instances=0`：沒人用時不收費。第一次開頁面要多等幾秒冷啟動。

## 開放給誰用

```bash
# 加人（或改成 group:xxx@<your-domain> 開給整個群組）
gcloud iap web add-iam-policy-binding --resource-type=cloud-run --service=data-chatbox --region=asia-east1 \
    --member=user:someone@<your-domain> --role=roles/iap.httpsResourceAccessor

# 看目前有誰
gcloud iap web get-iam-policy --resource-type=cloud-run --service=data-chatbox --region=asia-east1
```

2026-10-15 首次上線時只開給 `<you@your-domain>`。

### 開放給組織外的帳號（gmail 等）

`--iap` 預設用 Google 代管的 OAuth client，**只有同一個 GCP 組織的帳號能從瀏覽器登入**。組織外的帳號就算加進 IAM，也會在 Google 登入頁被擋下。要開放組織外的帳號，需要改用自建的 OAuth client（2026-11-05 已改）：

1. Console → Google Auth Platform：
   - Audience 改成 **External**，發布狀態設成 **In production**。只用基本 scope，不需要送審。不要用 Testing：每個人都要另外加進測試使用者名單，而且登入一陣子就失效。
   - Branding 要填 app name、support email、首頁、隱私權政策網址，以及 authorized domain。**不要上傳 logo**，上傳後就要送品牌驗證。
   - 同意畫面是整個專案共用的，改之前先看 Clients 頁有沒有其他 client。
2. Clients → 建立 Web application。建好之後，Authorized redirect URI 填 `https://iap.googleapis.com/v1/oauth/clientIds/<CLIENT_ID>:handleRedirect`。
3. 讓 IAP 改用這個 client。yaml 裡有 secret，放在 repo 外面，用完就刪：
   ```bash
   # iap_settings.yaml
   # access_settings:
   #   oauth_settings:
   #     client_id: <CLIENT_ID>
   #     client_secret: <CLIENT_SECRET>
   gcloud iap settings set iap_settings.yaml --resource-type=cloud-run --service=data-chatbox --region=asia-east1
   ```
4. 驗證：`curl -s -o /dev/null -w '%{redirect_url}' <服務網址>/`，轉址的 `client_id` 應該是新的 client。

改完之後加人的方式一樣，`--member=user:xxx@gmail.com` 就可以。不在名單的人會看到 IAP 的 "You don't have access"。

- 公司信箱不在 Google（例如 Microsoft 365）的同事，要先用那個信箱註冊 Google 帳號（「使用現有的電子郵件地址」），才能登入。
- 個人 gmail 不會因為同事離職而自動失效，要手動移除。

## 維運

- **使用紀錄**：每題一行 JSON 寫到 Cloud Logging，欄位有 user、question、thinking、seconds、error。可以在 Logs Explorer 用 `jsonPayload.component="data-chatbox"` 篩選。
- **改了新聞部定義之後**：照根目錄 walkthrough §4 重產 AI 定義檔，再重新部署 agent（`ai_context/ca_agent/deploy_agent.py`）。網頁本身不用重新部署。
- **改了 `notes.py` 的提醒內容**：要跟 `ai_context/news_dept_social_context.md` 的定義保持一致，改完跑 `python test_notes.py`。
- **費用**：
  - Cloud Run：閒置時 0。
  - Gemini Flash（深入分析撰寫）：每題輸入約 1 萬 token，費用不到 1 美分。
  - BigQuery：每題約 0.1–1.6 GB，因為 `news_dept_social` 的表是 view。
  - CA API：本身是否收費待到 Billing 確認。
