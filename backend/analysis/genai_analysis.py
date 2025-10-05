# analysis/genai_analysis.py
import os
import json
import hashlib
import logging
from cachetools import TTLCache
from dotenv import load_dotenv
# import your Gemini client library
import google.generativeai as genai   # pip install google-generativeai

# configure
GENAI_KEY = os.getenv("GOOGLE_API_KEY")
USE_GENAI = os.getenv("USE_GENAI", "true").lower() in ("1", "true", "yes")
GENAI_TIMEOUT = int(os.getenv("GENAI_TIMEOUT", "10"))

if GENAI_KEY:
    genai.configure(api_key=GENAI_KEY)

# simple TTL cache to avoid repeat calls
CACHE = TTLCache(maxsize=1024, ttl=3600)  # 1 hour cache

logger = logging.getLogger("genai_analysis")


def _make_cache_key(stats: dict) -> str:
    s = json.dumps(stats, sort_keys=True)
    return hashlib.sha256(s.encode()).hexdigest()


def _local_gene_advice(stats: dict) -> str:
    # safe rule-based fallback (keep short & useful)
    t = stats.get("avg_temp_C")
    r = stats.get("avg_rain_mm")
    w = stats.get("avg_wind_kmh")
    h = stats.get("avg_humidity_pct")
    c = stats.get("comfort_index")

    parts = []
    if t is not None:
        if t > 35: parts.append("Expect very hot conditions; avoid strenuous activity midday.")
        elif t > 28: parts.append("Warm temperatures expected; stay hydrated.")
        elif t < 15: parts.append("Cool conditions expected; bring a jacket.")
        else: parts.append("Temperatures look moderate.")

    if r is not None:
        if r > 10: parts.append("High chance of rain—carry rain gear.")
        elif r > 2: parts.append("Light showers possible.")
        else: parts.append("Mostly dry expected.")

    if h is not None and h > 75:
        parts.append("High humidity may cause discomfort.")
    if w is not None and w > 25:
        parts.append("Windy conditions likely—secure loose items.")

    if c is not None:
        if c >= 0.7: parts.append("Overall: comfortable for outdoor activities.")
        elif c >= 0.4: parts.append("Overall: fair; some discomfort possible.")
        else: parts.append("Overall: uncomfortable—consider indoor alternatives.")

    return " ".join(parts) or "Insufficient data to generate advice."


def generate_gene_analysis_genai(stats: dict, model: str = "models/text-bison-001", max_output_tokens: int = 150, temperature: float = 0.7) -> str:
    """
    Generate 'Gene' advice using Gemini (via google.generativeai).
    Falls back to _local_gene_advice on failure or if USE_GENAI is False.
    """
    if not stats:
        return _local_gene_advice(stats)

    # always use cached result when possible
    cache_key = _make_cache_key(stats)
    if cache_key in CACHE:
        return CACHE[cache_key]

    if not USE_GENAI or not GENAI_KEY:
        logger.info("GenAI disabled or missing key — using local fallback.")
        advice = _local_gene_advice(stats)
        CACHE[cache_key] = advice
        return advice

    # Build a concise, controlled prompt
    prompt = (
        "You are Gene, a concise and friendly weather analyst. "
        "Based on these summarized parameters, generate 2-4 short sentences with practical, actionable advice "
        "for a user planning outdoor activities. Do not include long disclaimers. Keep it under 120 words.\n\n"
        f"Data: {json.dumps(stats, indent=2)}\n\n"
        "Output:"
    )

    try:
        # NOTE: SDK method names may vary. This example uses genai.generate (adjust to your SDK)
        response = genai.generate(
            model=model,
            prompt=prompt,
            max_output_tokens=max_output_tokens,
            temperature=temperature,
        )
        # extract text depending on SDK response shape
        text = getattr(response, "text", None) or (response.candidates[0].content if getattr(response, "candidates", None) else str(response))
        text = text.strip()
        if not text:
            raise ValueError("Empty response from GenAI")
        CACHE[cache_key] = text
        return text
    except Exception as e:
        logger.exception("GenAI call failed; falling back to local rule-based advice: %s", e)
        advice = _local_gene_advice(stats)
        CACHE[cache_key] = advice
        return advice

