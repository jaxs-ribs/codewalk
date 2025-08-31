@codewalk/mobile-core

This package contains a minimal, UI‑agnostic client for the CodeWalk relay protocol used by the mobile app. It manages the WebSocket handshake, emits structured events, and provides a `sendUserText()` helper. It is framework‑agnostic and can be used from React Native (passing the global `WebSocket`) or from Node (passing a compatible `WebSocket` implementation).

Design

`connect({ ws, sid, tok, WebSocket })` returns a lightweight client with `on()/off()` for events and a `sendUserText(text)` method. The client sends the required `hello` message and then listens for server frames, unwrapping the inner payload when possible.

Basic usage (Node)

```ts
import { connect } from '@codewalk/mobile-core'
import WS from 'ws'

const c = connect({ ws: 'ws://127.0.0.1:3001/ws', sid: 'devsession0001', tok: 'devtoken0001x', WebSocket: WS as any })
c.on('helloAck', () => c.sendUserText('build a small cli tool please'))
c.on('ack', (a) => { console.log('ack:', a); c.close() })
```

React Native

```ts
import { connect } from '@codewalk/mobile-core'

const c = connect({ ws, sid, tok, WebSocket })
c.on('helloAck', () => c.sendUserText(input))
c.on('ack', (a) => setLastAck(a.text || 'received'))
```

Build

```bash
cd packages/mobile-core
npm install
npm run build
```

