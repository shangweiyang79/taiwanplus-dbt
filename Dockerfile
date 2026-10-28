# 每日資料檢查（Cloud Run Job dbt-daily-checks）的映像：dbt Fusion + 這個 dbt 專案。
# 部署與排程見 orchestration/README.md。chatbox 的映像另見 chatbox_app/Dockerfile。
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DBT_PROFILES_DIR=/app/profiles \
    DBT_ENGINE_NO_WARN_SEMANTIC_MANIFEST_VALIDATION=1

# 與本機、CI 同一版，避免「CI 過了、排程卻壞了」
RUN pip install --no-cache-dir dbt==2.0.9

WORKDIR /app
# 要帶進映像的檔案由 .dockerignore / .gcloudignore 控制
COPY . .

# build 時就確認專案能解析，有錯讓 build 失敗而不是排程時才發現
RUN GCP_PROJECT=build-check dbt parse --target prod

CMD ["bash", "orchestration/daily_checks.sh"]
