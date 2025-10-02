# Project Phasing

## Phase 1: Create HTML Canvas and Game Loop
Create the HTML5 canvas element and implement the basic game loop that continuously renders at 60fps.
**Definition of Done:** Open index.html in browser, see a blank canvas element filling most of the viewport, open console and verify "game loop running" prints every frame

## Phase 2: Draw Grid-Based Snake
Implement the snake as a series of connected squares on a grid system with basic rendering.
**Definition of Done:** Open index.html, see a static snake made of 3 green square segments positioned in the center of the canvas

## Phase 3: Implement Request Animation Frame
Use requestAnimationFrame to create a continuous loop for updating the snake's position
**Definition of Done:** Verify that the snake's position is updated on each frame, but does not yet move in a specific direction

## Phase 4: Add Directional Movement and Edge Wrapping
Make the snake move in one direction and wrap around to the left side when it reaches the right edge
**Definition of Done:** Open index.html, watch snake move smoothly to the right, when it reaches right edge it wraps around to left side

## Phase 5: Keyboard Direction Controls
Add keyboard input to change the snake's direction of movement.
**Definition of Done:** Open index.html, use arrow keys to change snake direction while it's moving, snake responds immediately without reversing into itself

## Phase 6: Add Food and Growth
Spawn food items randomly on the grid and make the snake grow when eating food.
**Definition of Done:** Open index.html, see red food square appear on grid, move snake to touch food, observe snake grow by one segment and new food spawn elsewhere

## Phase 7: Game Over Conditions
Implement collision detection for snake hitting walls or itself.
**Definition of Done:** Open index.html, steer snake into wall edge - game stops and displays "Game Over" message, restart and steer snake into its own body - game stops

## Phase 8: Implement Score Tracking and Portal Teleportation
Track and display the player's score based on food eaten, and add two portals (blue and orange) that teleport the snake between fixed positions, maintaining direction
**Definition of Done:** Open index.html, eat one food item - see score display 'Score: 1' on screen, eat three more food items - see score display 'Score: 4', see blue circle at position A and orange circle at position B, move snake into blue portal - snake instantly appears at orange portal position while maintaining direction, and score updates correctly after teleporting and eating food

## Phase 9: Implement Wall Dash
Add spacebar-triggered dash that lets the snake pass through walls briefly.
**Definition of Done:** Open index.html, position snake facing wall, press spacebar - see snake pass through wall and emerge on opposite side with brief invincibility effect

## Phase 10: Add Eating Sound
Implement a crunch sound effect when the snake eats food.
**Definition of Done:** Open index.html, eat food item - hear distinct crunch sound through speakers, eat multiple food items rapidly - sounds play cleanly without clipping

## Phase 11: Add Portal Teleport Sound
Add a whoosh sound effect when using portals.
**Definition of Done:** Open index.html, move snake through portal - hear whoosh sound effect, use portals multiple times - sounds play smoothly without overlap issues
