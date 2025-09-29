# Project Phasing

## Phase 1: Create Game Canvas
Set up the basic HTML structure with a canvas element.

**Definition of Done:** Open index.html in browser and see a 400×400 pixel bordered canvas centered on the page.

## Phase 2: Draw the Snake
Create the snake as an array of coordinates and render it on the canvas.

**Definition of Done:** Refresh the page and see a 3-segment snake (drawn as squares) in the center of the canvas.

## Phase 3: Add Movement Controls
Implement continuous snake movement and arrow-key direction changes.

**Definition of Done:** Press an arrow key and watch the snake move one square per frame in that direction; pressing a different arrow key changes direction.

## Phase 4: Generate Food
Add a single food pellet at a random free position on the canvas.

**Definition of Done:** Refresh the page and see one colored square (food) that does not overlap the snake.

## Phase 5: Implement Eating and Growth
Detect head-to-food collision, increase snake length by one segment, and respawn food.

**Definition of Done:** Move the snake’s head onto the food; the snake grows by one segment and the food immediately reappears at a new empty position.

## Phase 6: Add Wall Collision
End the game when the snake’s head hits any canvas edge.

**Definition of Done:** Drive the snake into a wall; the snake stops moving and “Game Over” is drawn on the canvas.

## Phase 7: Add Self Collision
End the game when the snake’s head collides with its own body.

**Definition of Done:** Make the snake head overlap any body segment; movement stops and “Game Over” is drawn on the canvas.