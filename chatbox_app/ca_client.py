"""Conversational Analytics API 的薄包裝：建立對話、送出問題、把串流回應整理成事件。

事件（kind, payload）：
    progress   str          思考 / 進度文字（顯示在狀態列）
    data       dict         {"rows": list[dict], "sql": str}；sql 可能是產生的或命中的範例查詢
    chart      dict         Vega-Lite spec
    final      str          最終回答（markdown）
    followups  list[str]    建議追問
    error      str
"""
import re
import uuid

from google.cloud import geminidataanalytics as gda

from config import AGENT_NAME, PARENT

_CJK = re.compile(r"[一-鿿]")

FAST = gda.ChatRequest.ThinkingMode.FAST
THINKING = gda.ChatRequest.ThinkingMode.THINKING
_TextType = gda.TextMessage.TextType


class ChatClient:
    def __init__(self, credentials):
        self._client = gda.DataChatServiceClient(credentials=credentials)

    def new_conversation(self):
        conv = self._client.create_conversation(
            parent=PARENT,
            conversation_id=f"chatbox-{uuid.uuid4().hex[:16]}",
            conversation=gda.Conversation(agents=[AGENT_NAME]),
        )
        return conv.name

    def ask(self, conversation, question, thinking=False):
        # 實測：FAST 模式常忽略 system_instruction 的語言規定，中文問題會用英文回答，所以在訊息裡再講一次
        text = question + ("\n\n（請用繁體中文回答）" if _CJK.search(question) else "")
        request = gda.ChatRequest(
            parent=PARENT,
            messages=[gda.Message(user_message=gda.UserMessage(text=text))],
            conversation_reference=gda.ConversationReference(
                conversation=conversation,
                data_agent_context=gda.DataAgentContext(data_agent=AGENT_NAME),
            ),
            thinking_mode=THINKING if thinking else FAST,
        )
        for msg in self._client.chat(request=request, timeout=600):
            yield from _events(msg.system_message)


def _events(sm):
    kind = sm._pb.WhichOneof("kind")
    if kind == "text":
        parts = [p for p in sm.text.parts if p.strip()]
        if not parts:
            return
        if sm.text.text_type == _TextType.FINAL_RESPONSE:
            yield "final", "".join(parts).strip()
        elif sm.text.text_type == _TextType.FOLLOWUP_QUESTIONS:
            yield "followups", [p.strip("-•* ").strip() for p in parts]
        else:
            # 進度訊息的 parts 是「標題」「說明」分開送，例如 ["Running a query", "SELECT …"]
            yield "progress", " · ".join(p.strip() for p in parts)
    elif kind == "data":
        d = sm.data
        sql = d.generated_sql or d.matched_query.example_query.sql_query
        if d.result.data:
            rows = type(d.result).to_dict(d.result)["data"]
            yield "data", {"rows": rows, "sql": sql}
        elif sql:
            yield "data", {"rows": [], "sql": sql}
    elif kind == "chart":
        if sm.chart.result.vega_config:
            yield "chart", type(sm.chart.result).to_dict(sm.chart.result)["vega_config"]
    elif kind == "error":
        yield "error", sm.error.text
