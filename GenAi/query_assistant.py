"""
GenAI Natural Language Query Layer for Azure Supply Chain Analytics
---------------------------------------------------------------------
Connects to Azure SQL Database, converts a natural-language question into
SQL using an Azure AI Foundry model deployment (text-to-SQL), executes it,
and generates a short narrative summary of the results (RAG-style: the
summary is grounded in the actually-retrieved data, not hallucinated).

Author: Harsh Gosai
"""

import os
import sys
import pyodbc
from openai import AzureOpenAI


# ---------------------------------------------------------------------------
# 1. Configuration - all secrets read from environment variables.
#    Never hardcode credentials in this file.
# ---------------------------------------------------------------------------

AZURE_OPENAI_ENDPOINT = os.environ.get("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_API_KEY = os.environ.get("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_DEPLOYMENT = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1-mini-2")
AZURE_OPENAI_API_VERSION = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")

SQL_SERVER = os.environ.get("SQL_SERVER")          # e.g. sql-supplychain-harsh.database.windows.net
SQL_DATABASE = os.environ.get("SQL_DATABASE")      # e.g. db-supplychain
SQL_USERNAME = os.environ.get("SQL_USERNAME")      # e.g. harshadmin
SQL_PASSWORD = os.environ.get("SQL_PASSWORD")

REQUIRED_VARS = {
    "AZURE_OPENAI_ENDPOINT": AZURE_OPENAI_ENDPOINT,
    "AZURE_OPENAI_API_KEY": AZURE_OPENAI_API_KEY,
    "SQL_SERVER": SQL_SERVER,
    "SQL_DATABASE": SQL_DATABASE,
    "SQL_USERNAME": SQL_USERNAME,
    "SQL_PASSWORD": SQL_PASSWORD,
}


def check_env():
    missing = [k for k, v in REQUIRED_VARS.items() if not v]
    if missing:
        print("Missing required environment variables:")
        for m in missing:
            print(f"  - {m}")
        print("\nSet these before running the script. See README for instructions.")
        sys.exit(1)


# ---------------------------------------------------------------------------
# 2. Azure SQL connection + schema introspection
# ---------------------------------------------------------------------------

def get_sql_connection():
    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER=tcp:{SQL_SERVER},1433;"
        f"DATABASE={SQL_DATABASE};"
        f"UID={SQL_USERNAME};"
        f"PWD={SQL_PASSWORD};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(conn_str)


def get_schema_summary(conn, max_tables=25):
    """
    Pulls table + column names/types from the database so the LLM knows
    what it's allowed to query against. Keeps it compact to save tokens.
    """
    cursor = conn.cursor()
    cursor.execute("""
        SELECT TOP 500
            t.TABLE_NAME,
            c.COLUMN_NAME,
            c.DATA_TYPE
        FROM INFORMATION_SCHEMA.TABLES t
        JOIN INFORMATION_SCHEMA.COLUMNS c
            ON t.TABLE_NAME = c.TABLE_NAME
        WHERE t.TABLE_TYPE = 'BASE TABLE'
        ORDER BY t.TABLE_NAME, c.ORDINAL_POSITION
    """)
    rows = cursor.fetchall()

    schema = {}
    for table, column, dtype in rows:
        schema.setdefault(table, []).append(f"{column} ({dtype})")

    lines = []
    for table, cols in list(schema.items())[:max_tables]:
        lines.append(f"Table {table}: " + ", ".join(cols))
    return "\n".join(lines)


def run_sql(conn, sql_query):
    cursor = conn.cursor()
    cursor.execute(sql_query)
    columns = [desc[0] for desc in cursor.description]
    rows = cursor.fetchall()
    return columns, rows


# ---------------------------------------------------------------------------
# 3. Azure AI Foundry (Azure OpenAI) client
# ---------------------------------------------------------------------------

def get_openai_client():
    return AzureOpenAI(
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_key=AZURE_OPENAI_API_KEY,
        api_version=AZURE_OPENAI_API_VERSION,
    )


def generate_sql(client, schema_text, user_question):
    system_prompt = (
        "You are a SQL expert working with Azure SQL Database (T-SQL syntax). "
        "Given a database schema and a natural language question, generate ONE "
        "valid, safe, read-only T-SQL SELECT query that answers the question.\n\n"
        "Rules:\n"
        "- Only generate SELECT statements. Never INSERT, UPDATE, DELETE, DROP, or ALTER.\n"
        "- Use TOP instead of LIMIT (T-SQL syntax).\n"
        "- Only reference tables/columns that exist in the schema provided.\n"
        "- Return ONLY the raw SQL query, no explanation, no markdown code fences.\n\n"
        f"Schema:\n{schema_text}"
    )

    response = client.chat.completions.create(
        model=AZURE_OPENAI_DEPLOYMENT,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_question},
        ],
        temperature=0,
        max_tokens=400,
    )
    sql = response.choices[0].message.content.strip()

    # Strip accidental markdown fences if the model adds them anyway
    sql = sql.replace("```sql", "").replace("```", "").strip()
    return sql


def generate_summary(client, user_question, columns, rows, max_rows=20):
    # Keep the payload small: sample first N rows only
    sample = rows[:max_rows]
    table_preview = ", ".join(columns) + "\n"
    table_preview += "\n".join(", ".join(str(v) for v in row) for row in sample)

    system_prompt = (
        "You are a data analyst. Given a user's question and the query results "
        "(a data sample), write a concise 2-3 sentence narrative summary of the "
        "key insight. Be specific with numbers where possible. Do not invent "
        "data not present in the sample."
    )
    user_prompt = (
        f"Question: {user_question}\n\n"
        f"Result row count: {len(rows)}\n"
        f"Data sample:\n{table_preview}"
    )

    response = client.chat.completions.create(
        model=AZURE_OPENAI_DEPLOYMENT,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        temperature=0.3,
        max_tokens=200,
    )
    return response.choices[0].message.content.strip()


# ---------------------------------------------------------------------------
# 4. Safety guard - only allow SELECT statements to execute
# ---------------------------------------------------------------------------

def is_safe_select(sql_query):
    normalized = sql_query.strip().lower()
    if not normalized.startswith("select"):
        return False
    forbidden = ["insert", "update", "delete", "drop", "alter", "truncate", "exec", "merge"]
    return not any(word in normalized for word in forbidden)


# ---------------------------------------------------------------------------
# 5. Main interactive loop
# ---------------------------------------------------------------------------

def main():
    check_env()

    print("Connecting to Azure SQL Database...")
    conn = get_sql_connection()
    print("Connected.\n")

    print("Reading schema...")
    schema_text = get_schema_summary(conn)
    print("Schema loaded.\n")

    client = get_openai_client()

    print("=" * 60)
    print("GenAI Supply Chain Query Assistant")
    print("Ask a question in plain English. Type 'exit' to quit.")
    print("=" * 60)

    while True:
        user_question = input("\nYour question: ").strip()
        if user_question.lower() in ("exit", "quit"):
            break
        if not user_question:
            continue

        try:
            sql_query = generate_sql(client, schema_text, user_question)
            print(f"\nGenerated SQL:\n{sql_query}\n")

            if not is_safe_select(sql_query):
                print("Generated query was not a safe SELECT statement. Skipping execution.")
                continue

            columns, rows = run_sql(conn, sql_query)
            print(f"Rows returned: {len(rows)}")
            for row in rows[:10]:
                print(row)
            if len(rows) > 10:
                print(f"... ({len(rows) - 10} more rows not shown)")

            summary = generate_summary(client, user_question, columns, rows)
            print(f"\nSummary:\n{summary}")

        except Exception as e:
            print(f"Error: {e}")

    conn.close()
    print("\nConnection closed. Goodbye.")


if __name__ == "__main__":
    main()
