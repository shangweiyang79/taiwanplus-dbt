{#
  dev：一律寫進 target.schema（例如 dbt_joy），不污染正式 dataset。
  prod：有設定 +schema 的 model 直接寫進該 dataset（例如 social_hub），
        不會變成 dbt 預設的 <target>_<custom> 串接名稱，
        這樣 Looker Studio 接的 social_hub.<view> 名稱可以原封不動。
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
