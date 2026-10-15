# Data Chatbox（Streamlit）的 Cloud Run 映像。部署步驟見 README.md。
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY .streamlit/ ./.streamlit/
COPY *.py ./

# 規則（模式判斷、資料提醒）有錯就讓 build 失敗，而不是上線後才發現
RUN python test_notes.py && python -c "import ca_client, notes, config"

# Cloud Run 會給 PORT（預設 8080）
CMD ["sh", "-c", "streamlit run app.py --server.port=${PORT:-8080} --server.address=0.0.0.0"]
