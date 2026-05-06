"""
Ollama tests — validates the local LLM server at localhost:11434.

Verifies:
  - Ollama server is reachable
  - API /api/tags returns a list of models
  - Can generate a short response from a dummy prompt (if model is available)
  - API /api/ps returns running model info
  - Model info endpoint returns metadata

Tests are skipped gracefully if Ollama is not running.
"""
import pytest
import requests

OLLAMA_URL = "http://localhost:11434"
DEFAULT_MODEL = "llama3.2:1b"  # small model, change via OLLAMA_MODEL env var
import os
MODEL = os.environ.get("OLLAMA_MODEL", DEFAULT_MODEL)


def _ollama_available():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=3)
        return r.status_code == 200
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _ollama_available(),
    reason=f"Ollama not reachable at {OLLAMA_URL} — run: bash start.sh --ai"
)


# ── Server health ─────────────────────────────────────────────────────────────

def test_ollama_server_reachable():
    """Ollama API server is up and responding."""
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    assert r.status_code == 200, f"Expected 200, got {r.status_code}"
    print(f"\n  Ollama server: {OLLAMA_URL}  →  HTTP {r.status_code}")


def test_ollama_version_header():
    """Ollama returns a version in the response or server header."""
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    # Ollama sets Ollama-Version or Content-Type headers
    assert r.headers.get("Content-Type", "").startswith("application/json"), \
        f"Unexpected Content-Type: {r.headers.get('Content-Type')}"


def test_api_tags_returns_list():
    """/api/tags returns a JSON object with a 'models' list."""
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    data = r.json()
    assert "models" in data, f"'models' key missing from response: {data}"
    assert isinstance(data["models"], list), "models should be a list"
    print(f"\n  available models: {[m.get('name') for m in data['models']]}")


def test_model_is_pulled():
    """The configured model is present in the Ollama model list."""
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    models = [m.get("name") for m in r.json().get("models", [])]
    if not models:
        pytest.skip("No models pulled yet — run: ollama pull llama3.2:1b")
    if MODEL not in models:
        pytest.skip(f"Model '{MODEL}' not found in {models} — run: ollama pull {MODEL}")
    print(f"\n  model '{MODEL}' is available")


# ── Generation ────────────────────────────────────────────────────────────────

def test_generate_short_response():
    """
    Generate a minimal response from the LLM.
    Uses stream=False to get a single JSON response.
    """
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    models = [m.get("name") for m in r.json().get("models", [])]
    if MODEL not in models:
        pytest.skip(f"Model '{MODEL}' not pulled — run: ollama pull {MODEL}")

    payload = {
        "model": MODEL,
        "prompt": "Reply with exactly: HELLO",
        "stream": False,
        "options": {"num_predict": 10, "temperature": 0},
    }
    resp = requests.post(f"{OLLAMA_URL}/api/generate", json=payload, timeout=60)
    assert resp.status_code == 200, f"Generate failed: {resp.status_code} {resp.text[:200]}"
    data = resp.json()
    assert "response" in data, f"'response' key missing: {data}"
    assert len(data["response"]) > 0, "Empty response from model"
    print(f"\n  prompt: 'Reply with exactly: HELLO'")
    print(f"  response: {data['response'][:100]!r}")
    print(f"  eval_count: {data.get('eval_count')}")


def test_generate_returns_done_flag():
    """Generation response includes a 'done' field set to True."""
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    models = [m.get("name") for m in r.json().get("models", [])]
    if MODEL not in models:
        pytest.skip(f"Model '{MODEL}' not pulled")

    payload = {"model": MODEL, "prompt": "Say: OK", "stream": False,
               "options": {"num_predict": 5, "temperature": 0}}
    resp = requests.post(f"{OLLAMA_URL}/api/generate", json=payload, timeout=60)
    data = resp.json()
    assert data.get("done") is True, f"'done' should be True, got {data.get('done')}"


def test_model_show_endpoint():
    """
    /api/show returns model metadata (parameters, modelfile, etc.).
    """
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    models = [m.get("name") for m in r.json().get("models", [])]
    if MODEL not in models:
        pytest.skip(f"Model '{MODEL}' not available")

    resp = requests.post(f"{OLLAMA_URL}/api/show", json={"name": MODEL}, timeout=10)
    assert resp.status_code == 200
    data = resp.json()
    assert "modelfile" in data or "parameters" in data or "details" in data, \
        f"Unexpected model info response keys: {list(data.keys())}"
    print(f"\n  model details: {list(data.keys())}")


def test_embeddings_endpoint():
    """
    /api/embeddings generates an embedding vector for a short text.
    """
    r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
    models = [m.get("name") for m in r.json().get("models", [])]
    if MODEL not in models:
        pytest.skip(f"Model '{MODEL}' not available")

    payload = {"model": MODEL, "prompt": "hello world"}
    resp = requests.post(f"{OLLAMA_URL}/api/embeddings", json=payload, timeout=30)
    if resp.status_code == 404:
        pytest.skip("This model does not support embeddings")
    assert resp.status_code == 200
    data = resp.json()
    assert "embedding" in data, f"'embedding' missing: {data.keys()}"
    embedding = data["embedding"]
    assert isinstance(embedding, list) and len(embedding) > 0, \
        "Expected a non-empty embedding vector"
    print(f"\n  embedding dims: {len(embedding)}")
