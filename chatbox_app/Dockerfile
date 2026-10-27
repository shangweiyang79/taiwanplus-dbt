# Data Chatbox（Streamlit）的 Cloud Run 映像。部署步驟見 README.md。
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY .streamlit/ ./.streamlit/
COPY assets/ ./assets/
COPY *.py ./

# 規則（模式判斷、資料提醒）有錯就讓 build 失敗，而不是上線後才發現
# import 檢查只需要一個專案 ID 字串；假值只在這一行有效，執行時仍由 Cloud Run 決定
RUN export GCP_PROJECT=build-check && python test_notes.py && python test_ca_client.py && python -c "import ca_client, notes, config, narrator"

# Cloud Run 會給 PORT（預設 8080）
CMD ["sh", "-c", "streamlit run app.py --server.port=${PORT:-8080} --server.address=0.0.0.0"]
