"""Send one prompt to Ollama and stream the response.

Run:  python examples/beginner/02_ollama_generate.py
Prereq: bash start.sh --ai   (Ollama on localhost:11434, a model pulled)
"""
import json
import os
import urllib.request

HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2:1b")
PROMPT = "In one sentence, what is a vector database?"

req = urllib.request.Request(
    f"{HOST}/api/generate",
    data=json.dumps({"model": MODEL, "prompt": PROMPT, "stream": True}).encode(),
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(req) as resp:
    for line in resp:
        chunk = json.loads(line)
        print(chunk.get("response", ""), end="", flush=True)
        if chunk.get("done"):
            print()
            break
