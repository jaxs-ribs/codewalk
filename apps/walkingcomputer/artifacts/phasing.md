# Project Phasing

## Phase 1: Initialize Database
Set up PostgreSQL database and create the core dog profiles table.
**Definition of Done:** Run `psql \d dogs` and see columns matching the schema (id, name, age, breed, photo_url, bio, created_at) plus the migrations table.

## Phase 2: Create Dog Profile Endpoint
Build the POST /api/dogs endpoint to create new dog profiles.
**Definition of Done:** Run `curl -X POST localhost:3000/api/dogs -H "Content-Type: application/json" -d '{"name": "Buddy", "breed": "Labrador", "age": 3}'` and receive 201 + created dog with id.

## Phase 3: Retrieve Dogs Endpoint
Create the GET /api/dogs endpoint to fetch all dog profiles.
**Definition of Done:** Run `curl localhost:3000/api/dogs` and receive an array with the dog created in Phase 2.

## Phase 4: Swipe Tracking
Add the swipes table and POST /api/swipe endpoint to record swipe actions.
**Definition of Done:** Run `curl -X POST localhost:3000/api/swipe -d '{"dogId": 1, "targetId": 2, "like": true}'` and receive 200 {success: true}.

## Phase 5: Match Detection
Implement the logic that detects mutual likes and creates matches.
**Definition of Done:** Run `curl -X POST localhost:3000/api/swipe -d '{"dogId": 2, "targetId": 1, "like": true}'` followed by `psql -c "SELECT count(*) FROM matches"` and see count = 1.

## Phase 6: Dog Card Component
Build the React component that displays dog profiles.
**Definition of Done:** Import and render the DogCard component with test props; see photo, name, age, breed displayed on screen.

## Phase 7: Touch Gestures
Add swipe gesture detection to the dog card.
**Definition of Done:** Touch and drag the card; console.log outputs show the swipe direction and position updating in real-time.

## Phase 8: Complete Swipe Flow
Connect swipe gestures to the API and show match notifications.
**Definition of