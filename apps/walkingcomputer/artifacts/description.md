# Project Description

We're building a lightweight web app that delivers daily weather predictions for Kazakhstan. The core idea is simple: every day you'll get an updated forecast that highlights the regions expecting rain, storms, or temperature swings, so locals and travelers know what to pack.

The app pulls live data once a day, then formats it into plain language cards. Instead of raw numbers you'll see things like "North-west: heavy rain likely, carry waterproofs" or "Almaty: cooler, 22 °C, rain starts Wednesday morning." A small map overlay colors each oblast so you can spot warnings at a glance. We'll keep the palette calm and the layout mobile-first, because most users will check while heading out the door.

Tech-wise we'll host it as a static site on GitHub Pages. A GitHub Action runs a Python script every morning: it fetches open weather data, parses the Kazakh hydromet feed, writes a JSON file, and rebuilds the site. The front end is just HTML, CSS and a touch of vanilla JS that reads the JSON and renders the cards. No log-ins, no trackers, just open the URL and you have today's outlook. If the fetch ever fails the page quietly shows yesterday's data plus a small "checking for update" note so it never feels broken.

Extras we'll sneak in later: a Telegram bot that pastes the same summary each dawn, and a one-click toggle between Kazakh, Russian and English. But for launch the goal is rock-solid daily updates and a page that loads in under a second even on 3G.