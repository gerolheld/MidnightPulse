#!/usr/bin/env python3
"""Open-Meteo forecast for Midnight Pulse (no API key). Cached 15 min. Prints JSON."""
from pathlib import Path
import urllib.request, urllib.parse, json, time, sys
city = sys.argv[1] if len(sys.argv) > 1 else 'London'
cache = Path.home() / '.cache/midnight-pulse/weather.json'
cache.parent.mkdir(parents=True, exist_ok=True)
prev = {}
try: prev = json.loads(cache.read_text())
except (OSError, ValueError): pass
def get(url):
    with urllib.request.urlopen(url, timeout=12) as r: return json.load(r)
def kind(code):
    if code == 0: return 'clear', 'Ясно'
    if code in (1, 2): return 'partly', 'Малооблачно'
    if code == 3: return 'cloudy', 'Облачно'
    if code in (45, 48): return 'fog', 'Туман'
    if code in (71, 73, 75, 77, 85, 86): return 'snow', 'Снег'
    if code in (95, 96, 99): return 'storm', 'Гроза'
    if code in (51, 53, 55, 56, 57): return 'rain', 'Морось'
    return 'rain', 'Дождь'
try:
    if prev.get('query') == city and time.time() - prev.get('fetched', 0) < 900:
        print(json.dumps(prev['data'], ensure_ascii=False)); sys.exit(0)
    geo = get('https://geocoding-api.open-meteo.com/v1/search?' + urllib.parse.urlencode({'name': city, 'count': 1, 'language': 'ru', 'format': 'json'}))['results'][0]
    f = get('https://api.open-meteo.com/v1/forecast?' + urllib.parse.urlencode({
        'latitude': geo['latitude'], 'longitude': geo['longitude'],
        'current': 'temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m',
        'hourly': 'temperature_2m,weather_code,is_day', 'daily': 'temperature_2m_max,temperature_2m_min',
        'timezone': 'auto', 'forecast_days': 2}))
    c = f['current']; k, desc = kind(c['weather_code'])
    data = {'city': geo['name'], 'temp': round(c['temperature_2m']), 'feels': round(c['apparent_temperature']),
            'kind': k, 'desc': desc, 'day': bool(c['is_day']), 'wind': round(c['wind_speed_10m']),
            'humidity': round(c['relative_humidity_2m']), 'max': round(f['daily']['temperature_2m_max'][0]),
            'min': round(f['daily']['temperature_2m_min'][0]), 'hours': []}
    h = f['hourly']
    for i, t in enumerate(h['time']):
        if t > c['time'] and len(data['hours']) < 6:
            data['hours'].append({'time': t[11:16], 'temp': round(h['temperature_2m'][i]), 'kind': kind(h['weather_code'][i])[0], 'day': bool(h['is_day'][i])})
    cache.write_text(json.dumps({'query': city, 'fetched': time.time(), 'data': data}, ensure_ascii=False))
    print(json.dumps(data, ensure_ascii=False))
except Exception:
    if prev.get('query') == city: print(json.dumps(prev['data'], ensure_ascii=False))
    else: print(json.dumps({'city': city, 'temp': '—', 'desc': 'Нет данных', 'kind': 'clear', 'day': False, 'hours': []}, ensure_ascii=False))
