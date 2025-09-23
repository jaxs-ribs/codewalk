```markdown
# Tic-Tac-Toe Game in JavaScript & HTML

## Overview
A simple, browser-based implementation that lets two human players take turns marking a 3×3 grid until one player forms a horizontal, vertical, or diagonal line.

## File Structure
```
index.html
style.css
app.js
```

## index.html
```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Tic-Tac-Toe</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>Tic-Tac-Toe</h1>
  <div id="board">
    <!-- 9 buttons representing the cells -->
    <button class="cell" data-index="0"></button>
    <button class="cell" data-index="1"></button>
    <button class="cell" data-index="2"></button>
    <button class="cell" data-index="3"></button>
    <button class="cell" data-index="4"></button>
    <button class="cell" data-index="5"></button>
    <button class="cell" data-index="6"></button>
    <button class="cell" data-index="7"></button>
    <button class="cell" data-index="8"></button>
  </div>
  <p id="status">Current player: X</p>
  <button id="restart">Restart</button>

  <script src="app.js"></script>
</body>
</html>
```

## style.css (minimal)
```css
#board {
  display: grid;
  grid-template-columns: repeat(3, 100px);
  gap: 5px;
}
.cell {
  width: 100px;
  height: 100px;
  font-size: 2rem;
}
```

## app.js (core logic)
```javascript
const cells = document.querySelectorAll('.cell');
const statusText = document.getElementById('status');
const restartBtn = document.getElementById('restart');

let board = Array(9).fill(null); // 0..8
let currentPlayer = 'X';       // or 'O'
let gameActive = true;

const winningCombos = [
  [0,1,2], [3,4,5], [6,7,8], // rows
  [0,3,6], [1,4,7], [2,5,8], // cols
  [0,4,8], [2,4,6]           // diags
];

function handleClick(e) {
  const idx = e.target.dataset.index;
  if (!gameActive || board[idx]) return;

  board[idx] = currentPlayer;
  e.target.textContent = currentPlayer;

  if (checkWin()) {
    statusText.textContent = `${currentPlayer} wins!`;
    gameActive = false;
  } else if (board.every(Boolean)) {
    statusText.textContent = 'Draw!';
    gameActive = false;
  } else {
    currentPlayer = currentPlayer === 'X' ? 'O' : 'X';
    statusText.textContent = `Current player: ${currentPlayer}`;
  }
}

function checkWin() {
  return winningCombos.some(combo =>
    combo.every(i => board[i] === currentPlayer)
  );
}

function restart() {
  board = Array(9).fill(null);
  currentPlayer = 'X';
  gameActive = true;
  statusText.textContent = `Current player: X`;
  cells.forEach(btn => btn.textContent = '');
}

cells.forEach(btn => btn.addEventListener('click', handleClick));
restartBtn.addEventListener('click', restart);
```

## How to Run
1. Save the three files in the same folder.
2. Open `index.html` in any modern browser.
3. Click cells to play; use the Restart button to reset.

## Possible Enhancements
- Scoreboard
- Computer AI opponent
- Animated UI or sound effects
- Responsive grid sizing
```