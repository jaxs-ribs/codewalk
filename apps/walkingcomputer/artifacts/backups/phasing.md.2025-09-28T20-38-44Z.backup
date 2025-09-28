# Project Phasing

## Phase 1: Core Swipe Interface
So first we'll build the heart of the app - that satisfying swipe mechanism everyone's familiar with. We'll set up React Native with Expo to get us going fast, then create the swipeable card component using react-native-deck-swiper. Each card needs to show a name, age, brief bio, and a photo placeholder we'll add later. We'll implement swipe gestures for left (nope) and right (yep), plus those handy yes/no buttons for folks who prefer tapping. The cards will stack nicely and animate smoothly as you swipe through them.
**Definition of Done:** Open the app and swipe five cards - you should be able to swipe left or right on each card with smooth animations, and see them stack naturally with visible name/age/bio fields on every card.

## Phase 2: Data Management
Then we'll wire up the brains behind all that swiping. We'll create a simple array of mock profiles with all the essential info - names, ages, bios, and photo URLs we'll fetch later. We'll implement basic state management to track whose profile we're showing, handle the swipe decisions, and manage the deck as cards get swiped away. When someone swipes right (yep), we'll store that in a "matches" array we can check later. We'll also add a reset function to shuffle the deck back when you run out of profiles.
**Definition of Done:** Swipe through all profiles to the end, verify the app shows an "out of profiles" message, press reset to reload the deck, then check console logs to confirm right swipes are being saved to the matches array.

## Phase 3: Chat System
We will do this later, this is just a placeholder for now.
**Definition of Done:** This is just a placeholder.

## Phase 4: Profile Polish
After that we'll make those profiles actually look good. We'll fetch real photos from placeholder services and display them properly in the cards. We'll add smooth animations when cards appear and disappear, plus little visual cues like colored borders when you swipe (green for yes, red for no). The card layout will get refined with better spacing, readable fonts, and a clean gradient background. We'll also add the profile indicator dots at the bottom showing how many profiles are left in the deck.
**Definition of Done:** Swipe through three profiles and verify photos load properly with smooth fade-in effects, check that yes/no swipes show green/red borders, confirm the profile counter dots update correctly, and verify all text is cleanly readable with good spacing.

## Phase 5: Match & Store
Finally we'll add that satisfying match notification when two people both swipe right. When a successful match happens, we'll show a celebratory modal with both names and a big "It's a match!" message. We'll persist the matches using AsyncStorage so they survive app restarts, and add a simple matches screen where you can see everyone you've matched with. We'll also implement basic profile persistence so the app remembers where you left off, and add the ability to clear all data if someone wants a fresh start.
**Definition of Done:** Create a test scenario where profile A likes profile B, then go back and like profile A with profile B - verify the match modal appears with both names, check that both profiles appear in the matches list, close and reopen the app to confirm matches persist, then test the clear data button to ensure everything resets properly.