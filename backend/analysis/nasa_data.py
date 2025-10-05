# analysis/nasa_data.py
import requests
import pandas as pd
from cachetools import TTLCache, cached

# simple in-memory cache so repeated demo calls are fast
cache = TTLCache(maxsize=256, ttl=3600)

@cached(cache)
def get_power_data(lat, lon, start, end, parameters="T2M_MAX,PRECTOTCORR,WS2M,RH2M"):
    """
    Fetch daily NASA POWER point data and return a time-indexed pandas DataFrame.
    start, end: strings 'YYYYMMDD' (e.g. '20100101')
    """
    BASE_URL = "https://power.larc.nasa.gov/api/temporal/daily/point"
    params = {
        "start": start,
        "end": end,
        "latitude": lat,
        "longitude": lon,
        "community": "AG",
        "parameters": parameters,
        "format": "JSON"
    }

    resp = requests.get(BASE_URL, params=params, timeout=30)
    resp.raise_for_status()
    j = resp.json()

    # robustly find parameter dictionary
    if "properties" in j and "parameter" in j["properties"]:
        param_dict = j["properties"]["parameter"]
    elif "features" in j and len(j["features"])>0:
        param_dict = j["features"][0]["properties"]["parameter"]
    else:
        raise ValueError("Unexpected NASA POWER response structure")

    # Build DataFrame from nested dict {param: {date: value}}
    df = pd.DataFrame({var: pd.Series(vals) for var, vals in param_dict.items()})
    # convert index to datetime
    df.index = pd.to_datetime(df.index, format="%Y%m%d")
    df.index.name = "date"

    # add wind in km/h if WS2M present
    if "WS2M" in df.columns:
        df["WS2M_kmh"] = df["WS2M"] * 3.6

    return df
