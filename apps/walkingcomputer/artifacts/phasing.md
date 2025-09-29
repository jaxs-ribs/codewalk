# Project Phasing

## Phase 1: Core Scraper
So first we'll build a lightweight Python scraper using requests and BeautifulSoup to pull today's weather data from a reliable Kazakhstan weather site, then parse out temperature, precipitation, and wind fields. We'll schedule it with cron to run daily at 06:00 Almaty time and store the raw HTML plus extracted JSON in a local sqlite table so we always have a history to check.

**Definition of Done:** Run `python scrape.py`, verify sqlite row count increases by 1 and JSON contains keys temp, precip, wind with non-null values.

## Phase 2: Prediction Engine
Then we'll add a simple prediction layer: take the last 7 scraped records, compute rolling averages for temp and precip, and expose a `/predict` Flask endpoint that returns tomorrow's forecast as JSON. We'll keep it stateless—no training, just moving averages—so it's fast and explainable.

**Definition of Done:** `curl /predict` returns 200 with JSON like {"temp":22,"precip":1.3} and values fall within ±2 σ of the 7-day history.

## Phase 3: Web Front-end
After that we'll spin up a minimal React page that fetches `/predict`, renders a clean card showing tomorrow's temp, rain chance, and wind, plus a tiny map dot for Kazakhstan. We'll host it on GitHub Pages and set the scraper to auto-push daily so the forecast refreshes without deploys.

**Definition of Done:** Open the live URL, see updated card within 5s, and confirm date stamp equals today's scrape run.