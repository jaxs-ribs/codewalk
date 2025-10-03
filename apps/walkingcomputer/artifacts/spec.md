# Project Description

Portal Snake is a modern twist on the classic game we all know. You'll guide your snake around the screen, eating food to grow longer while avoiding walls and your own tail. But here's the cool part - we've added portals that let you teleport from one side of the map to the other. It's basically the same addictive gameplay you remember, just way more interesting.

The game runs right in your browser with smooth animations that make every movement feel fluid. When you eat food, you'll hear satisfying sound effects that make each bite rewarding. The colors are bright and cheerful, so it's easy on the eyes during long sessions.

We've kept the controls super simple - just use your arrow keys to steer. As you play, the game gets faster and more challenging, so you'll need quick reflexes to beat your high score. The portal mechanic adds a whole new layer of strategy since you can use them to escape tight spots or reach food that's otherwise blocked.

It's perfect for quick breaks or long sessions, and since it's all HTML5, it'll run on any device with a web browser. No downloads, no fuss - just open it up and start playing.

# Project Phasing

## Phase 1: Core Game Canvas
Set up HTML5 canvas with 400x400 game area and initialize canvas context.
**Definition of Done:** Open index.html in browser, see 400x400 black canvas displayed.

## Phase 2: Game Loop Foundation
Implement requestAnimationFrame game loop running at 60fps with basic update/render cycle.
**Definition of Done:** Open browser console, see "Frame rendered" message appearing 60 times per second.

## Phase 3: Keyboard Input System
Add responsive keyboard controls for arrow keys with real-time input capture.
**Definition of Done:** Press arrow keys, see console.log output with pressed key name, verify keydown and keyup events are properly handled, and confirm the system accurately captures and processes keyboard input in real-time.

## Phase 4: Snake Data Structure
Create a data structure to represent the snake as an array of 10x10 pixel segments
**Definition of Done:** Write and test a function that initializes the snake data structure with 3 segments at the center of the game area

## Phase 5: Snake Rendering Implementation
Implement the rendering of the snake on the game screen using the created data structure
**Definition of Done:** Load the game and see the snake shape rendered correctly at the center of the screen

## Phase 6: Snake Visualization Styling
Style the rendered snake with the required green color and ensure it is visible on the game screen
**Definition of Done:** Load the game and verify that the snake is rendered as 3 green squares in the center, forming the snake shape

## Phase 7: Snake Rendering Validation
Validate that the snake rendering works correctly in different scenarios, such as game restart or window resize
**Definition of Done:** Test the game with multiple scenarios and verify that the snake is always rendered correctly at the center of the screen

## Phase 8: Snake Movement and Boundary Handling Implementation
Implement a velocity system to move the snake at regular intervals, handle direction changes based on user input, and add edge collision detection to wrap the snake to the opposite side of the screen when hitting borders
**Definition of Done:** Start game, see snake moving right automatically without any user input, press up arrow to change snake direction from right to up, and move snake off any edge to see it emerge from the opposite side continuing in the same direction

## Phase 9: Food System
Implement red food pellets that spawn randomly on grid avoiding snake positions.
**Definition of Done:** Load game, see one red square on grid not overlapping snake.

## Phase 10: Food Collision
Add collision detection between snake head and food, triggering snake growth.
**Definition of Done:** Guide snake to touch red food, see snake grow by one segment.

## Phase 11: Portal Rendering
Create portal pairs as blue circles at two random grid positions.
**Definition of Done:** Load game, see two blue circles on grid away from snake.

## Phase 12: Portal Teleportation
Implement portal teleportation when snake head touches portal, maintaining direction.
**Definition of Done:** Move snake into portal, see it emerge from paired portal continuing same direction.

## Phase 13: Movement Interpolation
Add smooth movement interpolation between grid positions for fluid motion.
**Definition of Done:** Press arrow key, see snake glide smoothly to next grid position.

## Phase 14: Eating Animation
Implement brief pulse animation when snake eats food pellet.
**Definition of Done:** Eat food, see food briefly scale up before disappearing.

## Phase 15: Portal Glow Effect
Add subtle pulsing glow animation to portal circles.
**Definition of Done:** Load game, observe portals slowly pulsing with glow effect.

## Phase 16: Sound Infrastructure
Set up Web Audio API context and basic sound manager system.
**Definition of Done:** Load game, check console to see "Audio context initialized" message.

## Phase 17: Eating Sound
Add crunch sound effect when snake eats food pellet.
**Definition of Done:** Eat food with speakers on, hear crunch sound play.

## Phase 18: Portal Sound
Implement whoosh sound effect for portal traversal.
**Definition of Done:** Travel through portal, hear whoosh effect play.