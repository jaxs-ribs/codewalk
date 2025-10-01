# Project Phasing

## Phase 1: Game Board Setup
Create the HTML structure with a canvas element and initialize the canvas context.
**Definition of Done:** Open index.html in browser, see a centered canvas element with visible border that's 600x600 pixels, open console and verify constants exist (GRID_SIZE=20, TILE_SIZE=30)

## Phase 2: Snake Rendering
Create the snake data structure as an array of coordinates and implement a drawing function that renders the snake segments.
**Definition of Done:** Load the page and see a 3-segment snake in center (head dark green, body light green), run console.log(snake) shows array with 3 coordinate objects

## Phase 3: Food System
Implement food generation that randomly places food on the board and draws it as a red circle.
**Definition of Done:** Open page, see a red circular food item randomly placed (not on snake), run console.log(foodPosition) to display coordinates

## Phase 4: Snake Movement and Direction Control Implementation
Implement basic movement of the snake using setInterval to move one grid space per frame in the current direction, and add keyboard event listeners for arrow keys to change the snake's direction
**Definition of Done:** Snake moves automatically in current direction at 150ms intervals. console.log(snake[0]) shows head position updating. Pressing arrow keys changes the snake's direction. console.log(direction) outputs 'UP', 'DOWN', 'LEFT', or 'RIGHT' on key press

## Phase 5: Food Collision
Detect when snake head overlaps with food and implement food consumption.
**Definition of Done:** Move snake into food and see food disappear, console.log('food eaten') appears in console

## Phase 6: Growth Mechanics
Add segment to snake tail when food is eaten and implement scoring system.
**Definition of Done:** After eating food, see snake grow by 1 segment, score counter shows 10, console.log(score) returns 10

## Phase 7: Wall Collision
Implement collision detection for wall boundaries that ends the game.
**Definition of Done:** Drive snake into wall and verify that the game movement stops immediately, the 'Game Over' message is displayed prominently on the screen, the final score is shown, and no further user input is accepted until the game is restarted.

## Phase 8: Collision Detection Implementation
Implement the collision detection algorithm to identify when the snake's head intersects with its body
**Definition of Done:** Write unit tests that verify collision detection works for various snake body configurations and assert true for collisions

## Phase 9: Game Over Logic Integration
Integrate the collision detection with the game's logic to trigger the 'Game Over' state when a self-collision occurs
**Definition of Done:** Drive snake into itself and verify 'Game Over' message is displayed, console.log(gameOver) returns true, and game state is updated accordingly

## Phase 10: Sound Effects
Add Web Audio API for eating food and game over sounds.
**Definition of Done:** Eat food and hear sound, trigger game over and hear different sound, console.log(audioContext.state) shows 'running'

## Phase 11: Smooth Animations
Replace setInterval with requestAnimationFrame and add visual enhancements.
**Definition of Done:** Snake movement appears smooth at 60fps, food has subtle bounce animation (console.log food.scale shows values changing)
# Project Phasing

## Phase 1: Game Board Setup
Create the HTML structure with a canvas element and initialize the canvas context.
**Definition of Done:** Open index.html in browser, see a centered canvas element with visible border that's 600x600 pixels, open console and verify constants exist (GRID_SIZE=20, TILE_SIZE=30)

## Phase 2: Snake Rendering
Create the snake data structure as an array of coordinates and implement a drawing function that renders the snake segments.
**Definition of Done:** Load the page and see a 3-segment snake in center (head dark green, body light green), run console.log(snake) shows array with 3 coordinate objects

## Phase 3: Food System
Implement food generation that randomly places food on the board and draws it as a red circle.
**Definition of Done:** Open page, see a red circular food item randomly placed (not on snake), run console.log(foodPosition) to display coordinates

## Phase 4: Snake Movement and Direction Control Implementation
Implement basic movement of the snake using setInterval to move one grid space per frame in the current direction, and add keyboard event listeners for arrow keys to change the snake's direction
**Definition of Done:** Snake moves automatically in current direction at 150ms intervals. console.log(snake[0]) shows head position updating. Pressing arrow keys changes the snake's direction. console.log(direction) outputs 'UP', 'DOWN', 'LEFT', or 'RIGHT' on key press

## Phase 5: Food Collision
Detect when snake head overlaps with food and implement food consumption.
**Definition of Done:** Move snake into food and see food disappear, console.log('food eaten') appears in console

## Phase 6: Growth Mechanics
Add segment to snake tail when food is eaten and implement scoring system.
**Definition of Done:** After eating food, see snake grow by 1 segment, score counter shows 10, console.log(score) returns 10

## Phase 7: Wall Collision
Implement collision detection for wall boundaries that ends the game.
**Definition of Done:** Drive snake into wall and verify that the game movement stops immediately, the 'Game Over' message is displayed prominently on the screen, the final score is shown, and no further user input is accepted until the game is restarted.

## Phase 8: Collision Detection Implementation
Implement the collision detection algorithm to identify when the snake's head intersects with its body
**Definition of Done:** Write unit tests that verify collision detection works for various snake body configurations and assert true for collisions

## Phase 9: Game Over Logic Integration
Integrate the collision detection with the game's logic to trigger the 'Game Over' state when a self-collision occurs
**Definition of Done:** Drive snake into itself and verify 'Game Over' message is displayed, console.log(gameOver) returns true, and game state is updated accordingly

## Phase 10: Sound Effects
Add Web Audio API for eating food and game over sounds.
**Definition of Done:** Eat food and hear sound, trigger game over and hear different sound, console.log(audioContext.state) shows 'running'

## Phase 11: Smooth Animations
Replace setInterval with requestAnimationFrame and add visual enhancements.
**Definition of Done:** Snake movement appears smooth at 60fps, food has subtle bounce animation (console.log food.scale shows values changing)

o

