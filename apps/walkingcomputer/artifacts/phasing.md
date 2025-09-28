# Project Phasing

## Phase 1: Core Matching
So first we'll build the swipe-based matching engine with dog profiles, owner authentication, and basic geolocation to find nearby pups. We'll store photos, breed, age, and temperament data in Firebase, then implement the familiar swipe gestures and mutual-match logic. **Definition of Done:** Two test users can swipe right on each other's dogs and see an instant match notification.

## Phase 2: Chat & Safety
Then we'll add secure in-app messaging so owners can coordinate without sharing personal contact info, plus report/block buttons and basic photo verification to keep pups safe. We'll integrate Sendbird for real-time chat and implement content moderation filters. **Definition of Done:** Matched owners can exchange 10+ messages with no personal data leakage.

## Phase 3: Quick Sniff Walk
After that we'll launch the sniff-walk planner: pick a neutral park, suggest 30-minute windows based on both calendars, and send push reminders 15 minutes before. We'll map dog-friendly routes and integrate weather APIs to suggest indoor alternatives. **Definition of Done:** Two matched users can schedule, complete, and rate a shared walk within 24 hours.