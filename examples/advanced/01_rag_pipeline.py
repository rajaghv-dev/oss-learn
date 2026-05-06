"""End-to-end RAG: embed samples/documents.txt with Ollama, store in pgvector,
retrieve top-k for a question, and generate an answer with Ollama.

Run:  python examples/advanced/01_rag_pipeline.py "what does pgvector do?"
Prereq: bash start.sh --ai
        ollama pull nomic-embed-text   (or set EMBED_MODEL)
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values

REPO = Path(__file__).resolve().parents[2]
DSN = os.environ.get("DATABASE_URL", "postgresql://oss:oss@localhost:5432/oss")
OLLAMA = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
GEN_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2:1b")
question = sys.argv[1] if len(sys.argv) > 1 else "what is pgvector used for?"


def embed(text: str) -> list[float]:
    req = urllib.request.Request(
        f"{OLLAMA}/api/embeddings",
        data=json.dumps({"model": EMBED_MODEL, "prompt": text}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["embedding"]


def generate(prompt: str) -> str:
    req = urllib.request.Request(
        f"{OLLAMA}/api/generate",
        data=json.dumps({"model": GEN_MODEL, "prompt": prompt, "stream": False}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["response"]


docs = [line.strip() for line in (REPO / "samples/documents.txt").read_text().splitlines() if line.strip()]
probe_dim = len(embed(docs[0]))

with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    cur.execute("DROP TABLE IF EXISTS rag_chunks;")
    cur.execute(f"CREATE TABLE rag_chunks (id SERIAL PRIMARY KEY, text TEXT, embedding VECTOR({probe_dim}));")
    rows = [(d, str(embed(d))) for d in docs]
    execute_values(cur, "INSERT INTO rag_chunks (text, embedding) VALUES %s", rows)

    q_emb = str(embed(question))
    cur.execute(
        "SELECT text FROM rag_chunks ORDER BY embedding <=> %s::vector ASC LIMIT 3;",
        (q_emb,),
    )
    context = "\n".join(r[0] for r in cur.fetchall())

prompt = f"Use only this context to answer.\n\nContext:\n{context}\n\nQuestion: {question}\nAnswer:"
print(f"Q: {question}\n")
print("Retrieved context:")
for line in context.splitlines():
    print(f"  - {line}")
print("\nA:", generate(prompt))
