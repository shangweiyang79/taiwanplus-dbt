"""Data Chatbox 的設定與憑證。

在 Cloud Run 上：服務本身以唯讀 SA data-chatbox-ro 執行，直接用預設憑證。
在本機：模擬同一個 SA（操作者需在 SA 上有 serviceAccountTokenCreator），確保本機測到的權限和線上一樣。
"""
import os
import sys

import google.auth
from google.auth import impersonated_credentials


def _project():
    """專案 ID：優先讀環境變數 GCP_PROJECT；Cloud Run 上沒設時用服務所在的專案。"""
    if os.environ.get("GCP_PROJECT"):
        return os.environ["GCP_PROJECT"]
    if "K_SERVICE" in os.environ:
        return google.auth.default()[1]
    sys.exit("請先設定環境變數 GCP_PROJECT（GCP 專案 ID，見 ../.env.example）")


PROJECT = _project()
LOCATION = "global"  # CA API 沒有亞洲 endpoint；global 可查 asia-east1 的 dataset
PARENT = f"projects/{PROJECT}/locations/{LOCATION}"
AGENT_NAME = f"{PARENT}/dataAgents/news-dept-social"  # 由 ai_context/ca_agent/deploy_agent.py 部署
SA_EMAIL = f"data-chatbox-ro@{PROJECT}.iam.gserviceaccount.com"
# 深入分析的撰寫模型（Vertex AI）。2026-10-15 實測 3.8-flash 撰寫 6–7.5 秒、穩定；換模型前先跑 eval_deep.py
NARRATOR_MODEL = "gemini-3.8-flash"

_SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]


def on_cloud_run():
    return "K_SERVICE" in os.environ


def credentials():
    creds, _ = google.auth.default(scopes=_SCOPES)
    if on_cloud_run():
        return creds
    # 本機 gcloud 預設的 quota project 可能是別的專案，改掛本專案
    return impersonated_credentials.Credentials(
        source_credentials=creds.with_quota_project(PROJECT),
        target_principal=SA_EMAIL,
        target_scopes=_SCOPES,
        lifetime=3600,
    )
