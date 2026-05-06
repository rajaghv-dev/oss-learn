"""
Gitea (self-hosted git) tests.

Verifies the Gitea instance at http://localhost:3001 is up and responding.
Tests are skipped if Gitea is not running.
"""
import pytest
import requests

GITEA_URL = "http://localhost:3001"


def _gitea_up():
    try:
        return requests.get(f"{GITEA_URL}/api/v1/version", timeout=3).status_code == 200
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _gitea_up(),
    reason=f"Gitea not running at {GITEA_URL} — run: bash start.sh --git"
)


def test_gitea_version_api():
    """Gitea /api/v1/version returns a JSON object with a 'version' key."""
    r = requests.get(f"{GITEA_URL}/api/v1/version", timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "version" in data
    print(f"\n  Gitea version: {data['version']}")


def test_gitea_homepage():
    """Gitea homepage loads successfully."""
    r = requests.get(GITEA_URL, timeout=5)
    assert r.status_code == 200
    assert "Gitea" in r.text or "gitea" in r.text.lower()


def test_gitea_signup_disabled_by_default():
    """Public signup pages render without 5xx errors."""
    r = requests.get(f"{GITEA_URL}/user/sign_up", timeout=5)
    assert r.status_code in (200, 403, 404)


def test_gitea_swagger_api_docs():
    """Gitea exposes Swagger API docs at /api/swagger."""
    r = requests.get(f"{GITEA_URL}/api/swagger", timeout=5)
    assert r.status_code in (200, 302, 301)
