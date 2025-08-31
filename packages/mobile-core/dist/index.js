"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.connect = connect;
function connect(opts) {
    const { ws, sid, tok, WebSocket } = opts;
    const wsock = new WebSocket(ws);
    const handlers = {};
    const emit = (ev, arg) => (handlers[ev] || []).forEach(fn => fn(arg));
    wsock.onopen = () => {
        emit('open', undefined);
        wsock.send(JSON.stringify({ type: 'hello', s: sid, t: tok, r: 'phone' }));
    };
    wsock.onmessage = (e) => {
        try {
            const v = JSON.parse(String(e.data));
            if (v && v.type === 'hello-ack')
                emit('helloAck', { sessionId: v.sessionId });
            else if (v && v.type === 'peer-joined')
                emit('peerJoined', { role: v.role });
            else if (v && v.type === 'peer-left')
                emit('peerLeft', { role: v.role });
            else if (v && v.type === 'session-killed')
                emit('sessionKilled', undefined);
            else if (v && v.type === 'frame') {
                let inner;
                try {
                    inner = v.frame ? JSON.parse(v.frame) : undefined;
                }
                catch { }
                emit('frame', { raw: v, inner });
                if (inner && inner.type === 'ack')
                    emit('ack', { text: inner.text, replyTo: inner.replyTo });
            }
        }
        catch (err) {
            emit('error', { message: String(err?.message || err) });
        }
    };
    wsock.onerror = (e) => emit('error', { message: String(e?.message || 'ws error') });
    wsock.onclose = () => { };
    return {
        on(ev, fn) { var _a; (handlers[_a = ev] || (handlers[_a] = [])).push(fn); },
        off(ev, fn) { const a = handlers[ev]; if (!a)
            return; const i = a.indexOf(fn); if (i >= 0)
            a.splice(i, 1); },
        sendUserText(text) { wsock.send(JSON.stringify({ type: 'user_text', text, final: true, source: 'phone' })); },
        close() { try {
            wsock.close();
        }
        catch { } }
    };
}
