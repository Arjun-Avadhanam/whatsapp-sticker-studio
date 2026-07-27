"""Backend tests. yt-dlp is mocked, so these run fast with no network."""

from unittest.mock import patch

from fastapi.testclient import TestClient

import main

client = TestClient(main.app)


def _info(formats):
    return {"formats": formats}


def test_extract_returns_mp4_url():
    info = _info(
        [{"url": "https://video.twimg.com/x.mp4", "ext": "mp4", "height": 720}]
    )
    with patch.object(main, "resolve_info", return_value=info):
        r = client.post("/extract", json={"url": "https://x.com/u/status/1"})

    assert r.status_code == 200
    body = r.json()
    assert body["mp4_url"].endswith(".mp4")
    assert body["kind"] == "video"


def test_picks_the_highest_resolution_mp4():
    info = _info(
        [
            {"url": "https://v/low.mp4", "ext": "mp4", "height": 240},
            {"url": "https://v/high.mp4", "ext": "mp4", "height": 1080},
            {"url": "https://v/mid.mp4", "ext": "mp4", "height": 480},
        ]
    )
    with patch.object(main, "resolve_info", return_value=info):
        r = client.post("/extract", json={"url": "https://x.com/u/status/1"})

    assert r.status_code == 200
    assert r.json()["mp4_url"].endswith("high.mp4")


def test_no_mp4_variant_returns_422():
    info = _info([{"url": "https://v/only.webm", "ext": "webm", "height": 720}])
    with patch.object(main, "resolve_info", return_value=info):
        r = client.post("/extract", json={"url": "https://x.com/u/status/1"})

    assert r.status_code == 422
    assert "error" in r.json()["detail"]


def test_resolve_failure_returns_422():
    with patch.object(main, "resolve_info", side_effect=RuntimeError("unavailable")):
        r = client.post("/extract", json={"url": "https://x.com/u/status/1"})

    assert r.status_code == 422
    assert "error" in r.json()["detail"]
