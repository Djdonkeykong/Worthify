"""
Worthify Artwork Identification Server
POST /identify -> identifies artwork from an image URL using SearchAPI.io + Claude Haiku
"""

import json
import logging
import os
import re
import time

import anthropic
import requests
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

load_dotenv()

SEARCHAPI_KEY = os.environ["SEARCHAPI_KEY"]
ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
DEBUG_ERRORS = os.getenv("DEBUG_ERRORS", "true").lower() not in {"0", "false", "no"}
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(level=LOG_LEVEL, format="%(levelname)s: %(message)s")
logger = logging.getLogger("worthify.artwork_server")

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
- estimated_value_range: return ONLY the numeric price or price range (for example "$500 - $3,000"). \
Do not include explanatory words, labels, or reasoning in this field. \
If the text has no pricing, use YOUR OWN knowledge of this artist's market to provide a range. \
For emerging/lesser-known artists, estimate based on comparable artists at a similar career stage. \
Never return null for this field if the artist is identified.
- value_reasoning: state clearly whether the range comes from the source text or your own art market knowledge.

Source text:
{raw_text}"""

STRICT_EXTRACT_PROMPT = """\
You are an art market expert. The following text describes an artwork. \
Return ONLY a valid JSON object - no markdown, no explanation, no extra keys. \
Use null only for fields you truly cannot determine even with your own knowledge.

Required keys:
identified_artist, artwork_title, year_estimate, style, medium_guess,
is_original_or_print, confidence_level, estimated_value_range,
value_reasoning, comparable_examples_summary

confidence_level: "low" | "medium" | "high"
is_original_or_print: "original" | "print" | "unknown"
estimated_value_range: return ONLY a numeric price or price range string (for example "$500 - $3,000"). \
No extra words or explanation. Use text data if available, otherwise apply your own art market knowledge. \
Never null if artist is identified.
value_reasoning: state whether range is from source text or your own knowledge.

Source text:
{raw_text}"""


class IdentifyRequest(BaseModel):
    image_url: str


class ClaudeParseError(Exception):
    def __init__(self, message: str, output_preview: str):
        super().__init__(message)
        self.output_preview = output_preview


CURRENCY_CODES = (
    "USD",
    "EUR",
    "GBP",
    "NOK",
    "SEK",
    "DKK",
    "CAD",
    "AUD",
    "CHF",
    "JPY",
    "CNY",
    "HKD",
    "SGD",
    "NZD",
)
CURRENCY_SYMBOLS = "$€£¥"
_CURRENCY_CODE_PATTERN = "|".join(CURRENCY_CODES)
_NUMBER_PATTERN = r"(?:\d{1,3}(?:[,\s]\d{3})+|\d+)(?:\.\d+)?"
_MAGNITUDE_PATTERN = r"(?:\s?(?:[kmb]\b|million\b|billion\b))?"
_CURRENCY_AMOUNT_PATTERN = (
    rf"(?:[{re.escape(CURRENCY_SYMBOLS)}]\s*{_NUMBER_PATTERN}{_MAGNITUDE_PATTERN}"
    rf"|(?:{_CURRENCY_CODE_PATTERN})\s*{_NUMBER_PATTERN}{_MAGNITUDE_PATTERN}"
    rf"|{_NUMBER_PATTERN}{_MAGNITUDE_PATTERN}\s*(?:{_CURRENCY_CODE_PATTERN}))"
)
_PRICE_RANGE_PATTERN = re.compile(
    rf"({_CURRENCY_AMOUNT_PATTERN})\s*(?:to|[-–—])\s*({_CURRENCY_AMOUNT_PATTERN})",
    re.IGNORECASE,
)
_PRICE_AMOUNT_PATTERN = re.compile(_CURRENCY_AMOUNT_PATTERN, re.IGNORECASE)
_PLAIN_NUMERIC_RANGE_PATTERN = re.compile(
    rf"({_NUMBER_PATTERN})\s*(?:to|[-–—])\s*({_NUMBER_PATTERN})"
)


def _truncate(text: str, limit: int = 500) -> str:
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[:limit] + "...[truncated]"


def _append_if_present(lines: list[str], value: object) -> None:
    if isinstance(value, str):
        text = value.strip()
        if text:
            lines.append(text)


def _extract_source_text(data: dict) -> str:
    lines: list[str] = []

    _append_if_present(lines, data.get("markdown"))
    _append_if_present(lines, data.get("answer"))
    _append_if_present(lines, data.get("snippet"))

    ai_overview = data.get("ai_overview")
    if isinstance(ai_overview, dict):
        _append_if_present(lines, ai_overview.get("answer"))
        _append_if_present(lines, ai_overview.get("text"))
        _append_if_present(lines, ai_overview.get("snippet"))

        blocks = ai_overview.get("blocks")
        if isinstance(blocks, list):
            for block in blocks:
                if isinstance(block, dict):
                    _append_if_present(lines, block.get("answer"))
                    _append_if_present(lines, block.get("text"))
                    _append_if_present(lines, block.get("snippet"))

    text_blocks = data.get("text_blocks")
    if isinstance(text_blocks, list):
        for block in text_blocks:
            if isinstance(block, dict):
                _append_if_present(lines, block.get("answer"))
                _append_if_present(lines, block.get("text"))
                _append_if_present(lines, block.get("snippet"))

    reference_links = data.get("reference_links")
    if isinstance(reference_links, list):
        for link in reference_links:
            if isinstance(link, dict):
                _append_if_present(lines, link.get("title"))
                _append_if_present(lines, link.get("snippet"))
                _append_if_present(lines, link.get("source"))

    organic_results = data.get("organic_results")
    if isinstance(organic_results, list):
        for result in organic_results[:8]:
            if isinstance(result, dict):
                _append_if_present(lines, result.get("title"))
                _append_if_present(lines, result.get("snippet"))
                _append_if_present(lines, result.get("source"))

    visual_matches = data.get("visual_matches")
    if isinstance(visual_matches, list):
        for match in visual_matches[:15]:
            if isinstance(match, dict):
                _append_if_present(lines, match.get("title"))
                _append_if_present(lines, match.get("source"))
                _append_if_present(lines, match.get("price"))

    deduped_lines: list[str] = []
    seen: set[str] = set()
    for line in lines:
        normalized = " ".join(line.split())
        if normalized and normalized not in seen:
            deduped_lines.append(normalized)
            seen.add(normalized)

    return "\n".join(deduped_lines).strip()


def _searchapi_params(image_url: str, engine: str) -> dict:
    params = {
        "engine": engine,
        "api_key": SEARCHAPI_KEY,
        "url": image_url,
    }

    if engine == "google_ai_mode":
        params["q"] = (
            "What artwork is this? Identify the artist, title, year created, artistic style "
            "or movement, medium (oil, watercolor, etc.), and whether this appears to be an "
            "original or a print/reproduction. "
            "Provide an estimated value range in USD for this specific piece if known. "
            "If the specific piece's value is unknown, provide the general market price range "
            "that this artist's works typically sell for (e.g. at auction, galleries, or online), "
            "and note whether the artist is emerging, mid-career, or established. "
            "Mention any comparable auction results or sales you are aware of."
        )

    return params


def _call_searchapi(image_url: str) -> str:
    """Call SearchAPI.io and return source text for Claude extraction."""
    attempts = [
        ("google_ai_mode", 2),
        ("google_lens", 1),
    ]

    last_data_keys: list[str] = []
    for engine, max_attempts in attempts:
        for attempt in range(1, max_attempts + 1):
            params = _searchapi_params(image_url=image_url, engine=engine)
            logger.info("SearchAPI request engine=%s attempt=%s", engine, attempt)

            resp = requests.get(
                "https://www.searchapi.io/api/v1/search", params=params, timeout=30
            )
            resp.raise_for_status()
            data = resp.json()
            last_data_keys = sorted(data.keys())

            raw = _extract_source_text(data)
            if raw:
                logger.info(
                    "SearchAPI returned %s characters of source text (engine=%s)",
                    len(raw),
                    engine,
                )
                logger.debug("SearchAPI preview: %s", _truncate(raw))
                return raw

            logger.warning(
                "SearchAPI response had no extractable text (engine=%s, attempt=%s, keys=%s)",
                engine,
                attempt,
                ",".join(last_data_keys),
            )
            if attempt < max_attempts:
                time.sleep(1.0)

    logger.info(
        "SearchAPI returned 0 characters of source text after retries. Last keys=%s",
        ",".join(last_data_keys),
    )
    return ""


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
    logger.info("Claude returned %s characters (strict=%s)", len(text), strict)

    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        preview = _truncate(text)
        logger.warning("Claude JSON parse failed (strict=%s): %s", strict, preview)
        raise ClaudeParseError(str(exc), preview) from exc


def _normalize_text_field(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        return text or None
    if isinstance(value, (int, float, bool)):
        return str(value)
    if isinstance(value, list):
        pieces = []
        for item in value:
            if item is None:
                continue
            pieces.append(str(item).strip())
        text = ", ".join(piece for piece in pieces if piece)
        return text or None
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=False)
    return str(value).strip() or None


def _clean_price_amount(amount: str) -> str:
    text = " ".join(amount.strip().split())
    text = re.sub(r"([$€£¥])\s+(\d)", r"\1\2", text)
    return text


def _normalize_estimated_value_range(value: object) -> str | None:
    text = _normalize_text_field(value)
    if not text:
        return None

    range_match = _PRICE_RANGE_PATTERN.search(text)
    if range_match:
        lower = _clean_price_amount(range_match.group(1))
        upper = _clean_price_amount(range_match.group(2))
        return f"{lower} - {upper}"

    amounts = []
    for match in _PRICE_AMOUNT_PATTERN.finditer(text):
        cleaned = _clean_price_amount(match.group(0))
        if cleaned not in amounts:
            amounts.append(cleaned)

    if amounts:
        has_range_signal = " to " in text.lower() or "-" in text or "–" in text or "—" in text
        if len(amounts) >= 2 and has_range_signal:
            return f"{amounts[0]} - {amounts[1]}"
        return amounts[0]

    plain_range = _PLAIN_NUMERIC_RANGE_PATTERN.search(text)
    if plain_range and any(
        keyword in text.lower()
        for keyword in ("value", "worth", "price", "estimate", "estimated")
    ):
        lower = plain_range.group(1).replace(" ", "")
        upper = plain_range.group(2).replace(" ", "")
        return f"{lower} - {upper}"

    return text


def _normalize_confidence(value: object) -> str:
    normalized = (_normalize_text_field(value) or "").lower()
    if normalized in {"high", "medium", "low"}:
        return normalized
    if "high" in normalized:
        return "high"
    if "low" in normalized:
        return "low"
    return "medium"


def _normalize_original_or_print(value: object) -> str:
    normalized = (_normalize_text_field(value) or "").lower()
    if normalized in {"original", "print", "unknown"}:
        return normalized
    if "print" in normalized:
        return "print"
    if "original" in normalized:
        return "original"
    return "unknown"


def _normalize_analysis_result(result: dict) -> dict:
    normalized = {
        "identified_artist": _normalize_text_field(result.get("identified_artist")),
        "artwork_title": _normalize_text_field(result.get("artwork_title")),
        "year_estimate": _normalize_text_field(result.get("year_estimate")),
        "style": _normalize_text_field(result.get("style")),
        "medium_guess": _normalize_text_field(result.get("medium_guess")),
        "is_original_or_print": _normalize_original_or_print(
            result.get("is_original_or_print")
        ),
        "confidence_level": _normalize_confidence(result.get("confidence_level")),
        "estimated_value_range": _normalize_estimated_value_range(
            result.get("estimated_value_range")
        ),
        "value_reasoning": _normalize_text_field(result.get("value_reasoning")),
        "comparable_examples_summary": _normalize_text_field(
            result.get("comparable_examples_summary")
        ),
    }
    return normalized


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/identify")
def identify(req: IdentifyRequest):
    if not req.image_url or not req.image_url.strip():
        raise HTTPException(status_code=400, detail="image_url is required")

    logger.info("Identify request received for image URL: %s", req.image_url)

    try:
        raw_text = _call_searchapi(req.image_url)
    except requests.HTTPError as exc:
        logger.exception("SearchAPI HTTP error")
        raise HTTPException(
            status_code=502, detail=f"SearchAPI.io error: {exc}"
        ) from exc
    except requests.RequestException as exc:
        logger.exception("SearchAPI request failed")
        raise HTTPException(
            status_code=502, detail=f"SearchAPI.io request failed: {exc}"
        ) from exc

    if not raw_text:
        logger.warning("Identify failed: SearchAPI returned no text")
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Could not identify artwork",
                "reason": "SearchAPI returned no text",
            },
        )

    try:
        raw_result = _parse_with_claude(raw_text, strict=False)
    except (ClaudeParseError, KeyError, IndexError) as first_exc:
        logger.warning("Retrying Claude parse with strict prompt: %s", first_exc)
        try:
            raw_result = _parse_with_claude(raw_text, strict=True)
        except (ClaudeParseError, KeyError, IndexError) as exc:
            logger.exception("Identify failed: Could not parse artwork data")
            detail = {
                "error": "Could not parse artwork data",
                "reason": str(exc),
            }
            if DEBUG_ERRORS:
                detail["debug"] = {
                    "searchapi_text_preview": _truncate(raw_text),
                    "claude_output_preview": getattr(exc, "output_preview", ""),
                }
            raise HTTPException(status_code=422, detail=detail) from exc

    if not isinstance(raw_result, dict):
        logger.error("Identify failed: Claude output is not a JSON object (%s)", type(raw_result).__name__)
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Could not parse artwork data",
                "reason": "Claude returned a non-object JSON payload.",
            },
        )

    result = _normalize_analysis_result(raw_result)
    result["disclaimer"] = (
        "This is an AI-generated estimate for informational purposes only. "
        "Not a certified appraisal."
    )
    logger.info(
        "Identify succeeded: artist=%s title=%s confidence=%s",
        result.get("identified_artist"),
        result.get("artwork_title"),
        result.get("confidence_level"),
    )
    return result
