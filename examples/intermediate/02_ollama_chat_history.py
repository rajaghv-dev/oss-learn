"""Multi-turn chat against Ollama /api/chat with rolling message history.

Run:  python examples/intermediate/02_ollama_chat_history.py
Prereq: bash start.sh --ai   (Ollama on localhost:11434, a model pulled)
"""
import json
import os
import sys
import urllib.error
import urllib.request

HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2:1b")

TURNS = [
    "My name is Ada. Remember it.",
    "What is the capital of France? Answer in one word.",
    "What name did I give you at the start?",
]


def chat(messages: list[dict]) -> str:
    payload = {"model": MODEL, "messages": messages, "stream": False}
    req = urllib.request.Request(
        f"{HOST}/api/chat",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)["message"]["content"].strip()


messages: list[dict] = []
try:
    for i, user_text in enumerate(TURNS, 1):
        messages.append({"role": "user", "content": user_text})
        reply = chat(messages)
        messages.append({"role": "assistant", "content": reply})
        print(f"[turn {i}] user      : {user_text}")
        print(f"[turn {i}] assistant : {reply}")
        print()
except urllib.error.URLError as e:
    print(f"[skip] cannot reach Ollama at {HOST}: {e.reason}")
    sys.exit(0)

print(f"history kept: {len(messages)} messages ({len(messages)//2} turns)")
