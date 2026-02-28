"""
Worthify Artwork Identification Server
POST /identify  →  identifies artwork from an image URL using SearchAPI.io + Claude Haiku
"""

import json
import os

import anthropic
import requests
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, HttpUrl

load_dotenv()

SEARCHAPI_KEY = os.environ["SEARCHAPI_KEY"]
ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")

app = FastAPI(title="Worthify Artwork Identifier", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)

anthropic_client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

EXTRACT_PROMPT = """\
You are an art market expert. Extract artwork identification data from the source text below, \
then return ONLY valid JSON with these exact keys (no extra keys, no markdown fences):

identified_artist, artwork_title, year_estimate, style, medium_guess,
is_original_or_print, confidence_level, estimated_value_range,
value_reasoning, comparable_examples_summary

Rules:
- Use null for any field you cannot determine from the text or your own knowledge.
- confidence_level must be one of: "low", "medium", "high"
- is_original_or_print must be one of: "original", "print", "unknown"
- estimated_value_range: use the specific price from the text if available. \
If the text has no pricing, use YOUR OWN knowledge of this artist's market to provide a range \
(e.g. "Artist's works typically: $500 – $3,000"). \
For emerging/lesser-known artists, estimate based on comparable artists at a similar career stage. \
Never return null for this field if the artist is identified.
- value_reasoning: state clearly whether the range comes from the source text or your own art market knowledge.

Source text:
{raw_text}"""

STRICT_EXTRACT_PROMPT = """\
You are an art market expert. The following text describes an artwork. \
Return ONLY a valid JSON object — no markdown, no explanation, no extra keys. \
Use null only for fields you truly cannot determine even with your own knowledge.

Required keys:
identified_artist, artwork_title, year_estimate, style, medium_guess,
is_original_or_print, confidence_level, estimated_value_range,
value_reasoning, comparable_examples_summary

confidence_level: "low" | "medium" | "high"
is_original_or_print: "original" | "print" | "unknown"
estimated_value_range: use text data if available, otherwise apply your own art market knowledge. \
Never null if artist is identified.
value_reasoning: state whether range is from source text or your own knowledge.

Source text:
{raw_text}"""


class IdentifyRequest(BaseModel):
    image_url: str


def _call_searchapi(image_url: str) -> str:
    """Call SearchAPI.io Google AI Mode with the artwork image. Returns raw text."""
    params = {
        "engine": "google_ai_mode",
        "api_key": SEARCHAPI_KEY,
        "q": (
            "What artwork is this? Identify the artist, title, year created, artistic style "
            "or movement, medium (oil, watercolor, etc.), and whether this appears to be an "
            "original or a print/reproduction. "
            "Provide an estimated value range in USD for this specific piece if known. "
            "If the specific piece's value is unknown, provide the general market price range "
            "that this artist's works typically sell for (e.g. at auction, galleries, or online), "
            "and note whether the artist is emerging, mid-career, or established. "
            "Mention any comparable auction results or sales you are aware of."
        ),
        "url": image_url,
    }
    resp = requests.get(
        "https://www.searchapi.io/api/v1/search", params=params, timeout=30
    )
    resp.raise_for_status()
    data = resp.json()

    # Try "markdown" field first, then concatenate text_blocks
    raw = data.get("markdown", "")
    if not raw:
        blocks = data.get("text_blocks") or data.get("ai_overview", {}).get("blocks", [])
        raw = "\n".join(
            b.get("answer", "") or b.get("text", "") for b in blocks if isinstance(b, dict)
        )
    return raw.strip()


def _parse_with_claude(raw_text: str, strict: bool = False) -> dict:
    """Send raw_text to Claude Haiku and parse the JSON response."""
    prompt_template = STRICT_EXTRACT_PROMPT if strict else EXTRACT_PROMPT
    message = anthropic_client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=512,
        messages=[
            {
                "role": "user",
                "content": prompt_template.format(raw_text=raw_text),
            }
        ],
    )
    text = message.content[0].text.strip()
    # Strip markdown fences if Claude added them despite the instruction
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    return json.loads(text)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/identify")
def identify(req: IdentifyRequest):
    if not req.image_url or not req.image_url.strip():
        raise HTTPException(status_code=400, detail="image_url is required")

    # Step 1: SearchAPI.io
    try:
        raw_text = _call_searchapi(req.image_url)
    except requests.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail=f"SearchAPI.io error: {exc}"
        ) from exc
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502, detail=f"SearchAPI.io request failed: {exc}"
        ) from exc

    if not raw_text:
        raise HTTPException(
            status_code=422,
            detail={"error": "Could not identify artwork", "reason": "SearchAPI returned no text"},
        )

    # Step 2: Parse with Claude Haiku (retry once with stricter prompt on JSON error)
    try:
        result = _parse_with_claude(raw_text, strict=False)
    except (json.JSONDecodeError, KeyError, IndexError):
        try:
            result = _parse_with_claude(raw_text, strict=True)
        except (json.JSONDecodeError, KeyError, IndexError) as exc:
            raise HTTPException(
                status_code=422,
                detail={"error": "Could not parse artwork data", "reason": str(exc)},
            ) from exc

    result["disclaimer"] = (
        "This is an AI-generated estimate for informational purposes only. "
        "Not a certified appraisal."
    )
    return result
