# Project Phasing

## Phase 1: Create database schema
**Description:** Create SQLite database with episodes table
**Definition of Done:** Run `sqlite3 toilet_tracker.db ".schema episodes"` and see table with columns: id, timestamp, urgency, notes

## Phase 2: Build basic logging form
**Description:** Create HTML form with urgency buttons (1-5) and notes field
**Definition of Done:** Open index.html, see 5 urgency buttons and notes text input field

## Phase 3: Implement database save functionality
**Description:** Connect form to database to save episode data
**Definition of Done:** Click urgency level 3, type "test" in notes, submit form, run `sqlite3 toilet_tracker.db "SELECT * FROM episodes"` and see saved row with urgency=3, notes="test"

## Phase 4: Add timestamp override feature
**Description:** Add ability to modify timestamp when logging past episodes
**Definition of Done:** Click "Change time", select timestamp 2 hours ago, save episode, run `sqlite3 toilet_tracker.db "SELECT timestamp FROM episodes WHERE id=1"` and see timestamp 2 hours before current time

## Phase 5: Build daily summary view
**Description:** Create page displaying today's logged episodes with urgency colors
**Definition of Done:** Open summary.html, see section showing today's date with list of all episodes logged today

## Phase 6: Add episode counter and average urgency
**Description:** Display total episodes and average urgency for today
**Definition of Done:** Add 3 episodes with urgency levels 2, 4, and 3, open summary.html, see "Total episodes: 3" and "Average urgency: 3.0"

## Phase 7: Implement CSV export
**Description:** Add button to download all data as CSV file
**Definition of Done:** Click "Export Data", open downloaded toilet_tracker.csv, see header row "timestamp,urgency,notes" followed by all logged episodes