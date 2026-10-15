"""深入分析：用 CA API 的 FAST 模式取數，再由 Gemini Flash 依同一套業務規則撰寫分析。

為什麼不用 CA API 的 THINKING 模式（2026-10-15 實測）：
- THINKING 一題約 32–34 秒，其中「讀完資料後撰寫分析」就占 20–22 秒，而且資料要等到最後才一起送回。
- FAST 取數（約 10–15 秒）＋ gemini-3.8-flash 撰寫（約 6–7.5 秒，可串流）總共約 18–21 秒；
  3 題判斷型問題的品質與 THINKING 相當。
- 撰寫規則直接讀已部署 agent 的 system_instruction，不在這裡另存一份。
- 實測模型偶爾會抄錯數字（例如 2,345,678 寫成 2,345,123），所以 prompt 要求逐字照抄，
  並用 unmatched_numbers 檢查回答中的數字是否都能在查詢結果裡找到。
"""
import json
import re
from functools import lru_cache

from google import genai
from google.cloud import geminidataanalytics as gda
from google.genai import types

from config import AGENT_NAME, NARRATOR_MODEL, PROJECT

TASK = """

## 你現在的工作
根據使用者的問題與下面的「查詢結果」撰寫分析：
- 只能使用查詢結果裡的數字；引用數字時逐字照抄（含千分位），不可改寫或憑記憶重打。成長率等推算值可以自己算，但要寫明是推算。
- 先給一兩句結論，再條列各單位 / 各平台的數字依據。精簡，不要重複列同樣的數字。
- 若查詢結果不足以回答，直接說明缺什麼，不要猜。
- 最後一行附「查詢範圍：範圍｜指標（每日流量或影片層）｜期間｜來源表」。
"""


@lru_cache(maxsize=1)
def _gemini(credentials):
    # 要重複使用同一個 client：臨時建立的 client 會在串流讀完前被回收，
    # 出現「Cannot send a request, as the client has been closed」（2026-10-15 評估時踩到）
    return genai.Client(vertexai=True, project=PROJECT, location="global", credentials=credentials)


@lru_cache(maxsize=1)
def _rules(credentials):
    agent = gda.DataAgentServiceClient(credentials=credentials).get_data_agent(name=AGENT_NAME)
    return agent.data_analytics_agent.published_context.system_instruction + TASK


def narrate(credentials, question, results, history=()):
    """串流產生分析文字（generator of str）。history：同一對話中先前的問題，讓追問有上下文。"""
    data = "\n\n".join(
        f"SQL:\n{r.get('sql') or '（命中範例查詢）'}\n結果（JSON）:\n{json.dumps(r['rows'], ensure_ascii=False)}"
        for r in results if r["rows"]
    )
    prior = "".join(f"- {q}\n" for q in history[-3:])
    prompt = (f"先前的問題（供理解追問的上下文）：\n{prior}\n" if prior else "") + f"問題：{question}\n\n查詢結果：\n{data}"
    stream = _gemini(credentials).models.generate_content_stream(
        model=NARRATOR_MODEL,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=_rules(credentials),
            temperature=0.2,
            thinking_config=types.ThinkingConfig(thinking_level="low"),
        ),
    )
    for chunk in stream:
        if chunk.text:
            yield chunk.text


def unmatched_numbers(answer, results):
    """回答中帶千分位的整數（≥ 1,000），在查詢結果裡找不到的。加總、差額等推算值也會被列出，所以只做提醒。"""
    values = {int(v) for r in results for row in r["rows"] for v in row.values()
              if isinstance(v, (int, float)) and not isinstance(v, bool) and float(v).is_integer()}
    # 排除「約 1,000 萬」這種概數寫法
    found = [int(n.replace(",", "")) for n in re.findall(r"(?<![\d.])\d{1,3}(?:,\d{3})+(?![\d.,])(?!\s*[萬億])", answer)]
    return sorted({n for n in found if n not in values})
