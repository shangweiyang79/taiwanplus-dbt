"""ca_agent 各腳本共用的常數與憑證。"""
import google.auth
from google.auth import impersonated_credentials

PROJECT = "ivory-airfoil-418408"
LOCATION = "global"  # CA API 沒有亞洲 endpoint；global 可查 asia-east1 的 dataset
PARENT = f"projects/{PROJECT}/locations/{LOCATION}"
AGENT_ID = "news-dept-social"
AGENT_NAME = f"{PARENT}/dataAgents/{AGENT_ID}"
SA_EMAIL = f"data-chatbox-ro@{PROJECT}.iam.gserviceaccount.com"
MAX_BILLED_BYTES = 5 * 1024**3

_SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]


def operator_credentials():
    """操作者自己的 ADC。gcloud 預設 quota project 是 taiwanplus-member-71778，改掛本專案。"""
    creds, _ = google.auth.default(scopes=_SCOPES)
    return creds.with_quota_project(PROJECT)


def sa_credentials():
    """模擬唯讀 SA data-chatbox-ro（操作者需在 SA 上有 serviceAccountTokenCreator）。"""
    return impersonated_credentials.Credentials(
        source_credentials=operator_credentials(),
        target_principal=SA_EMAIL,
        target_scopes=_SCOPES,
        lifetime=3600,
    )
