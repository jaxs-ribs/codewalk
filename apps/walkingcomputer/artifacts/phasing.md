# Project Phasing

## Phase 1: Project Setup
Create the basic project structure with HTML, CSS, and JavaScript files, and set up a simple Express server.
**Definition of Done:** Run `npm start`, open localhost:3000, see blank page with no errors.

## Phase 2: Database Schema
Set up SQLite database and create tables for users and messages.
**Definition of Done:** Run `sqlite3 chat.db ".schema users"`, see columns: id, username, password_hash, created_at.

## Phase 3: Registration API
Build the registration endpoint that hashes passwords and stores users in the database.
**Definition of Done:** Run `curl -X POST /api/register -d '{"username":"test","password":"pass123"}'`, receive 201 response with user ID.

## Phase 4: Login API
Create the login endpoint that validates credentials and returns JWT tokens.
**Definition of Done:** Run `curl -X POST /api/login -d '{"username":"test","password":"pass123"}'`, receive 200 response with JWT token.

## Phase 5: Socket.IO Connection
Integrate Socket.IO and establish real-time connection handling.
**Definition of Done:** Open browser console, see "Socket connected" message when page loads.

## Phase 6: Message Sending
Implement real-time message broadcasting through Socket.IO.
**Definition of Done:** Open two browser tabs, send message through console: `socket.emit('message', 'hello')`, see message appear in second tab's console.

## Phase 7: Message Storage
Add database persistence for messages with proper timestamps.
**Definition of Done:** Send message through Socket.IO, run `sqlite3 chat.db "SELECT * FROM messages LIMIT 1"`, see message row with content and timestamp.

## Phase 8: Message History
Create API endpoint to retrieve stored messages.
**Definition of Done:** Run `curl /api/messages`, receive JSON array with message objects containing content and timestamp.

## Phase 9: Basic UI
Build simple HTML interface with message display and input field.
**Definition of Done:** Open localhost:3000, see message list area and text input with send button, type and send message, see it appear in list.

## Phase 10: Authentication UI
Add registration and login forms to the interface.
**Definition of Done:** Open localhost:3000, see "Register" and "Login" forms, submit registration form, receive success message.

## Phase 11: Protected Chat
Connect authentication to Socket.IO, requiring valid JWT for sending messages.
**Definition of Done:** Login through UI, send message through form, see message appear with username attached.