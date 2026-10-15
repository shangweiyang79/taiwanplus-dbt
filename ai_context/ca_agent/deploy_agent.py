"""依 agent_config.yaml 建立或更新 Data Agent（projects/.../locations/global/dataAgents/news-dept-social）。

staging 與 published 兩份 context 設成一樣；BigQuery Studio 的 Agents 頁也看得到這個 agent。

用法（在 taiwanplus_dbt/ 下，先跑 build_agent_config.py）：
    python ai_context/ca_agent/deploy_agent.py
"""
import os

import yaml
from google.api_core import exceptions
from google.cloud import geminidataanalytics as gda
from google.protobuf import field_mask_pb2

from common import AGENT_ID, AGENT_NAME, MAX_BILLED_BYTES, PARENT, operator_credentials

HERE = os.path.dirname(os.path.abspath(__file__))


def build_context(cfg):
    tables = [
        gda.BigQueryTableReference(project_id=cfg["project"], dataset_id=cfg["dataset"], table_id=t)
        for t in cfg["tables"]
    ]
    return gda.Context(
        system_instruction=cfg["system_instruction"],
        datasource_references=gda.DatasourceReferences(bq=gda.BigQueryTableReferences(table_references=tables)),
        options=gda.ConversationOptions(
            datasource=gda.DatasourceOptions(big_query_max_billed_bytes=MAX_BILLED_BYTES)
        ),
        example_queries=[
            gda.ExampleQuery(natural_language_question=q["question"], sql_query=q["sql"])
            for q in cfg["example_queries"]
        ],
        glossary_terms=[
            gda.GlossaryTerm(display_name=g["term"], description=g["description"], labels=g["synonyms"])
            for g in cfg["glossary"]
        ],
    )


def main():
    with open(os.path.join(HERE, "agent_config.yaml"), encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    context = build_context(cfg)
    agent = gda.DataAgent(
        name=AGENT_NAME,
        display_name="新聞部社群成效（唯讀）",
        description="TaiwanPlus 新聞部（Newsroom + Talks + Connected）社群成效問答；只讀 news_dept_social。",
        data_analytics_agent=gda.DataAnalyticsAgent(staging_context=context, published_context=context),
    )
    client = gda.DataAgentServiceClient(credentials=operator_credentials())
    try:
        client.get_data_agent(name=AGENT_NAME)
        mask = field_mask_pb2.FieldMask(paths=["display_name", "description", "data_analytics_agent"])
        client.update_data_agent(data_agent=agent, update_mask=mask).result()
        print(f"已更新 {AGENT_NAME}")
    except exceptions.NotFound:
        client.create_data_agent(parent=PARENT, data_agent_id=AGENT_ID, data_agent=agent).result()
        print(f"已建立 {AGENT_NAME}")


if __name__ == "__main__":
    main()
