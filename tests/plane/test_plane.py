"""
Plane (project management) tests.

Verifies the Plane instance at http://localhost:4000 is up.
Skipped if Plane is not running.
"""
import pytest
import requests

PLANE_URL = "http://localhost:4000"


def _plane_up():
    try:
        return requests.get(PLANE_URL, timeout=3, allow_redirects=True).status_code < 500
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _plane_up(),
    reason=f"Plane not running at {PLANE_URL} — run: bash start.sh --plane"
)


def test_plane_root_loads():
    """Plane root URL responds (redirect or HTML)."""
    r = requests.get(PLANE_URL, timeout=10, allow_redirects=True)
    assert r.status_code < 500


def test_plane_api_health():
    """Plane API base responds without 5xx errors."""
    r = requests.get(f"{PLANE_URL}/api/", timeout=5, allow_redirects=True)
    assert r.status_code < 500
    print(f"\n  Plane API status: {r.status_code}")
