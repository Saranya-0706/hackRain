# app.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from analysis.nasa_data import get_power_data
from analysis.stats_computations import compute_weather_stats

app = FastAPI(title="NASA Weather Risk - Simple Test")

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
def weather_risk(req: RiskRequest):
    # build start/end strings for NASA POWER
    start = f"{req.start_year}0101"
    end = f"{req.end_year}1231"
    try:
        df = get_power_data(req.lat, req.lon, start, end)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"NASA API error: {e}")

    if df is None or df.empty:
        raise HTTPException(status_code=404, detail="No data returned from NASA for that location/date range")

    result = compute_weather_stats(df)
    return {"location": {"lat": req.lat, "lon": req.lon}, "start": start, "end": end, "result": result}

@app.get("/")
def root():
    return {"message": "NASA Weather Risk API (simple test) is running"}
