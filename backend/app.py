# app.py
import os

from dotenv import load_dotenv
load_dotenv()


import asyncio
from concurrent.futures import ThreadPoolExecutor
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from analysis.nasa_data import get_power_data
from analysis.stats_computations import compute_weather_stats
from analysis.genai_analysis import generate_gene_analysis_genai, _local_gene_advice

app = FastAPI(title="NASA Weather Risk - Simple Test")

# small threadpool for blocking GenAI calls
GENAI_THREADPOOL = ThreadPoolExecutor(max_workers=3)
GENAI_TIMEOUT = float(os.getenv("GENAI_TIMEOUT", "10"))

# Allow all origins for quick testing from Android / browser (safe for hackathon demo)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class RiskRequest(BaseModel):
    lat: float
    lon: float
    start_year: int = 2015
    end_year: int = 2023

@app.post("/api/weather_risk")
async def weather_risk(req: RiskRequest):
    # build start/end strings for NASA POWER
    start = f"{req.start_year}0101"
    end = f"{req.end_year}1231"
    try:
        df = get_power_data(req.lat, req.lon, start, end)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"NASA API error: {e}")

    if df is None or df.empty:
        raise HTTPException(status_code=404, detail="No data returned from NASA for that location/date range")

    # 2) compute stats (sync)
    result = compute_weather_stats(df)

    # 3) generate gene advice using threadpool + timeout
    use_genai = os.getenv("USE_GENAI", "true").lower() in ("1", "true", "yes")
    if use_genai:
        loop = asyncio.get_running_loop()
        try:
            gene_advice = await asyncio.wait_for(
                loop.run_in_executor(GENAI_THREADPOOL, generate_gene_analysis_genai, result),
                timeout=GENAI_TIMEOUT
            )
        except Exception as e:
            # fallback to local rule-based advice on timeout/error
            gene_advice = _local_gene_advice(result)
    else:
        gene_advice = _local_gene_advice(result)

    result["gene_advice"] = gene_advice



    return {"location": {"lat": req.lat, "lon": req.lon}, "start": start, "end": end, "result": result}

@app.get("/")
def root():
    return {"message": "NASA Weather Risk API (simple test) is running"}
