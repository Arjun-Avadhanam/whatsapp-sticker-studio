"""Minimal X/Twitter media extractor.

Resolves a tweet URL to a direct mp4 URL using yt-dlp. It only *resolves* — it
never downloads the video (the app does that). Kept server-side so a yt-dlp
update fixes Twitter-format breakage without shipping a new app build.
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import yt_dlp

app = FastAPI()


class ExtractRequest(BaseModel):
    url: str


def resolve_info(url: str) -> dict:
    """Resolve (do NOT download) the tweet's media metadata via yt-dlp."""
    with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as ydl:
        return ydl.extract_info(url, download=False)


def pick_mp4(info: dict) -> str:
    """Highest-resolution mp4 variant among the resolved formats."""
    mp4s = [
        f
        for f in info.get("formats", [])
        if f.get("ext") == "mp4" and f.get("url")
    ]
    if not mp4s:
        raise RuntimeError("no mp4 variant available")
    return max(mp4s, key=lambda f: f.get("height") or 0)["url"]


@app.post("/extract")
def extract(req: ExtractRequest):
    try:
        info = resolve_info(req.url)
        return {"mp4_url": pick_mp4(info), "kind": "video"}
    except Exception as e:  # extraction is inherently fragile — degrade cleanly
        raise HTTPException(status_code=422, detail={"error": str(e)})
