# analysis/stats_computations.py
import math

def compute_weather_stats(df):
    """
    Simple average-based stats for testing.
    Returns: dict with avg_temp, avg_rainfall, avg_windspeed_kmh, avg_humidity, comfort_index
    """
    if df is None or df.empty:
        return {"error": "no data"}

    def safe_mean(col):
        if col in df and df[col].dropna().size > 0:
            return round(float(df[col].mean()), 2)
        return None

    avg_temp = safe_mean("T2M_MAX") or safe_mean("T2M")   # fallback if T2M_MAX not present
    avg_rain = safe_mean("PRECTOTCORR")
    avg_wind = safe_mean("WS2M_kmh") or (safe_mean("WS2M") and round(safe_mean("WS2M") * 3.6, 2))
    avg_hum = safe_mean("RH2M")

    out = {
        "avg_temp_C": avg_temp,
        "avg_rain_mm": avg_rain,
        "avg_wind_kmh": avg_wind,
        "avg_humidity_pct": avg_hum,
    }

    # Simple comfort index:
    # score components normalized between 0..1 then weighted. This is just for testing.
    if all(v is not None for v in [avg_temp, avg_rain, avg_wind, avg_hum]):
        temp_score = max(0.0, 1.0 - (abs(avg_temp - 25.0) / 30.0))   # ideal 25°C
        hum_score = max(0.0, 1.0 - (avg_hum / 100.0))               # lower humidity better
        wind_score = max(0.0, 1.0 - (avg_wind / 50.0))             # strong wind lowers score
        rain_score = max(0.0, 1.0 - (avg_rain / 50.0))             # heavy rain lowers score

        # simple weighted sum
        comfort = (0.4 * temp_score) + (0.25 * hum_score) + (0.2 * wind_score) + (0.15 * rain_score)
        out["comfort_index"] = round(max(0.0, min(1.0, comfort)), 2)
    else:
        out["comfort_index"] = None

    return out
