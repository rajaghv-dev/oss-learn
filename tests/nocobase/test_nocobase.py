"""
NocoBase (low-code platform) tests.

Verifies the NocoBase instance at http://localhost:13000 is up.
Skipped if NocoBase is not running.
"""
import pytest
import requests

NOCOBASE_URL = "http://localhost:13000"


def _nocobase_up():
    try:
        return requests.get(NOCOBASE_URL, timeout=3, allow_redirects=True).status_code < 500
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _nocobase_up(),
    reason=f"NocoBase not running at {NOCOBASE_URL} — run: bash start.sh --nocobase"
)


def test_nocobase_root_loads():
    """NocoBase root URL responds successfully."""
    r = requests.get(NOCOBASE_URL, timeout=10, allow_redirects=True)
    assert r.status_code < 500


def test_nocobase_api_responds():
    """NocoBase API endpoint responds without 5xx errors."""
    r = requests.get(f"{NOCOBASE_URL}/api/", timeout=5, allow_redirects=True)
    assert r.status_code < 500
    print(f"\n  NocoBase API status: {r.status_code}")
