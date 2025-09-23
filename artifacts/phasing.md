Phase One — Draw the Board  
We start by painting a soft dark canvas that fills the browser window, then overlay a quiet grid of forty by forty squares in a mid gray so the player senses space without clutter. This sets the calm stage where color will later sing, and it proves the layout engine is ready. Done means you open index dot html and see only the dark grid with no scroll bars.

Phase Two — Spawn the Snake  
Next we place a five segment snake on the grid, each block a flat mid gray for now, moving right one square every quarter second. We wire the arrow keys to change its heading, and we keep the segments linked so the tail follows the head. Remember, P is stored in the balls, so we treat each segment as a ball container. This gives us the core motion loop, and it is finished when you can steer the snake around the grid without breaking the chain.

Phase Three — Add Edible Light  
Now we drop a single pulsing food square on a random empty cell; the food gently grows and shrinks to ninety percent opacity and back every half second. When the head hits the food, the snake gains one segment at the tail and a new food appears elsewhere. This delivers the reward cycle, and we know it works when you can eat three foods in a row and feel the tiny burst each time.

Phase Four — Breathe Life with Color  
Here we swap the flat colors for living gradients: the snake body becomes a flowing sweep from cyan to magenta that slides along as it moves, the head glows a little brighter, and upon eating, the entire snake flashes white then fades back to the sweep over half a second. Food becomes a soft star with a faint halo. The game now feels alive, and the test is simple: play for five seconds and notice you cannot look away.

Phase Five — End and Restart Gracefully  
Finally we detect wall and self collisions, then stop motion and show a quiet game over message plus a gentle prompt to press space and restart. Pressing space clears the board, resets score to zero, and spawns a new snake and first food. With this, the loop is complete and polished, and we ship when you can lose, restart, and lose again without ever reaching for the mouse.