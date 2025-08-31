#!/usr/bin/env node
import { connect } from '../packages/mobile-core/dist/index.js'
import WebSocket from 'ws'

const ws = process.env.RELAY_WS_URL
const sid = process.env.RELAY_SESSION_ID
const tok = process.env.RELAY_TOKEN
const text = process.env.BOT_TEXT || 'hello from mobile-core'

if (!ws || !sid || !tok) {
  console.error('[bot-js] missing env RELAY_WS_URL/RELAY_SESSION_ID/RELAY_TOKEN')
  process.exit(2)
}

let timer
const c = connect({ ws, sid, tok, WebSocket })
c.on('helloAck', () => {
  console.log('\x1b[36m[bot-js]\x1b[0m hello-ack; sending user_text')
  c.sendUserText(text)
  timer = setTimeout(() => { console.error('[bot-js] timeout waiting for ack'); process.exit(1) }, 10000)
})
c.on('ack', (a) => {
  clearTimeout(timer)
  console.log('\x1b[32m[bot-js]\x1b[0m ack received', a?.text || '')
  c.close()
  process.exit(0)
})
c.on('error', (e) => {
  console.error('\x1b[31m[bot-js]\x1b[0m error', e.message)
})

