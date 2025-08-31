export type Events = {
  open: void
  helloAck: { sessionId: string }
  frame: { raw: any, inner?: any }
  ack: { text?: string, replyTo?: string }
  peerJoined: { role: string }
  peerLeft: { role: string }
  sessionKilled: void
  error: { message: string }
}

export type Listener<T> = (ev: T) => void

export interface Client {
  on<K extends keyof Events>(ev: K, fn: Listener<Events[K]>): void
  off<K extends keyof Events>(ev: K, fn: Listener<Events[K]>): void
  sendUserText(text: string): void
  close(): void
}

export type WebSocketCtor = new (url: string) => { onopen: any; onmessage: any; onerror: any; onclose: any; send(data: any): any; close(): any }

export function connect(opts: { ws: string, sid: string, tok: string, WebSocket: WebSocketCtor }): Client {
  const { ws, sid, tok, WebSocket } = opts
  const wsock = new WebSocket(ws)
  const handlers: Record<string, Function[]> = {}
  const emit = (ev: keyof Events, arg: any) => (handlers[ev as string] || []).forEach(fn => (fn as any)(arg))

  wsock.onopen = () => {
    emit('open', undefined as any)
    wsock.send(JSON.stringify({ type: 'hello', s: sid, t: tok, r: 'phone' }))
  }
  wsock.onmessage = (e: any) => {
    try {
      const v = JSON.parse(String(e.data))
      if (v && v.type === 'hello-ack') emit('helloAck', { sessionId: v.sessionId })
      else if (v && v.type === 'peer-joined') emit('peerJoined', { role: v.role })
      else if (v && v.type === 'peer-left') emit('peerLeft', { role: v.role })
      else if (v && v.type === 'session-killed') emit('sessionKilled', undefined as any)
      else if (v && v.type === 'frame') {
        let inner: any | undefined
        try { inner = v.frame ? JSON.parse(v.frame) : undefined } catch {}
        emit('frame', { raw: v, inner })
        if (inner && inner.type === 'ack') emit('ack', { text: inner.text, replyTo: inner.replyTo })
      }
    } catch (err: any) {
      emit('error', { message: String(err?.message || err) })
    }
  }
  wsock.onerror = (e: any) => emit('error', { message: String(e?.message || 'ws error') })
  wsock.onclose = () => {}

  return {
    on(ev, fn) { (handlers[ev as string] ||= []).push(fn as any) },
    off(ev, fn) { const a = handlers[ev as string]; if (!a) return; const i = a.indexOf(fn as any); if (i >= 0) a.splice(i, 1) },
    sendUserText(text: string) { wsock.send(JSON.stringify({ type: 'user_text', text, final: true, source: 'phone' })) },
    close() { try { wsock.close() } catch {} }
  }
}
