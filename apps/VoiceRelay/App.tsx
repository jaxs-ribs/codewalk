/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { StatusBar, Text, useColorScheme, StyleSheet, View, Platform, Pressable, TextInput } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

// Allow use of process.env via babel inline-dotenv
declare const process: any;

type HealthStatus = 'checking' | 'connected' | 'disconnected';

// Unified configuration from .env (inlined at build time)
const ENV_WS: string | undefined = process.env.RELAY_WS_URL;
const ENV_SID: string | undefined = process.env.RELAY_SESSION_ID;
const ENV_TOK: string | undefined = process.env.RELAY_TOKEN;

// Helpers to normalize WS and build Health without relying on URL.host quirks
const normalizeWs = (raw?: string | null): string | null => {
  if (!raw || !raw.trim()) return null;
  let u = raw.trim();
  // Ensure /ws path and adapt emulator hosts
  try {
    const parsed = new URL(u);
    if (Platform.OS === 'android' && (parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1')) {
      parsed.hostname = '10.0.2.2';
    } else if (Platform.OS === 'ios' && parsed.hostname === 'localhost') {
      parsed.hostname = '127.0.0.1';
    }
    parsed.pathname = '/ws';
    u = parsed.toString().replace(/\/$/, '');
  } catch {
    // Fallback: simple normalization
    if (!/\/ws$/.test(u)) u = u.replace(/\/?$/, '/ws');
  }
  return u;
};

const wsToHealth = (wsUrl?: string | null): string | null => {
  const u = normalizeWs(wsUrl);
  if (!u) return null;
  // Replace scheme and path by string ops to avoid URL polyfill inconsistencies
  const http = u.replace(/^wss?:\/\//, 'http://').replace(/\/ws$/, '');
  return `${http}/health`;
};

const RELAY_HEALTH_URL = wsToHealth(ENV_WS);

function App() {
  const isDarkMode = useColorScheme() === 'dark';
  const [status, setStatus] = useState<HealthStatus>('checking');
  const [lastCheckedAt, setLastCheckedAt] = useState<Date | null>(null);
  const [latencyMs, setLatencyMs] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [wsState, setWsState] = useState<'idle' | 'connecting' | 'open' | 'closed' | 'error'>('idle');
  const [wsUrl, setWsUrl] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [lastEvent, setLastEvent] = useState<string>('');
  const [lastPayload, setLastPayload] = useState<string>('');
  const [lastAck, setLastAck] = useState<string>('');
  const [input, setInput] = useState<string>('');
  const [showDetails, setShowDetails] = useState<boolean>(false);
  const wsRef = useRef<WebSocket | null>(null);
  const hbRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [closeInfo, setCloseInfo] = useState<string>('');

  const colors = useMemo(
    () => ({
      bg: isDarkMode ? '#000' : '#fff',
      fg: isDarkMode ? '#fff' : '#000',
      good: '#2ecc71',
      bad: '#e74c3c',
      dim: isDarkMode ? '#9aa0a6' : '#5f6368',
    }),
    [isDarkMode]
  );

  useEffect(() => {
    let mounted = true;

    async function checkOnce() {
      const started = Date.now();
      setStatus((s) => (s === 'checking' ? s : 'checking'));
      const ac = new AbortController();
      const t = setTimeout(() => ac.abort(), 5000);
      try {
        if (!RELAY_HEALTH_URL) throw new Error('Missing WS URL');
        const res = await fetch(RELAY_HEALTH_URL, { signal: ac.signal });
        const ok = res.ok;
        // Optional JSON shape: { ok: true }
        let bodyOk = false;
        try {
          const data = await res.clone().json();
          bodyOk = !!(data && (data.ok === true || data.status === 'ok'));
        } catch (_) {
          // Non-JSON or empty body is fine; rely on HTTP ok
        }
        const elapsed = Date.now() - started;
        if (!mounted) return;
        setLatencyMs(elapsed);
        setLastCheckedAt(new Date());
        setStatus(ok || bodyOk ? 'connected' : 'disconnected');
      } catch (_) {
        if (!mounted) return;
        setLatencyMs(null);
        setLastCheckedAt(new Date());
        setStatus('disconnected');
      } finally {
        clearTimeout(t);
      }
    }

    // Initial check immediately, then every 10s
    checkOnce();
    timerRef.current = setInterval(checkOnce, 10000);
    return () => {
      mounted = false;
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  // Helper to adapt ws://localhost URLs for Android emulator
  const adaptWsUrl = (u: string) => {
    try {
      const url = new URL(u);
      if (Platform.OS === 'android' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1')) {
        url.hostname = '10.0.2.2';
      } else if (Platform.OS === 'ios' && url.hostname === 'localhost') {
        url.hostname = '127.0.0.1';
      }
      // Normalize path strictly to "/ws" (no trailing slash) to avoid 404 on upgrade
      url.pathname = '/ws';
      return url.toString();
    } catch {
      return u;
    }
  };

  const disconnect = () => {
    if (hbRef.current) {
      clearInterval(hbRef.current);
      hbRef.current = null;
    }
    if (wsRef.current) {
      try { wsRef.current.close(); } catch {}
    }
    wsRef.current = null;
    setWsState('closed');
    setCloseInfo('');
  };

  const connect = async () => {
    // Do not gate on health; try once when values are present
    if (wsState === 'connecting' || wsState === 'open') return;
    setLastEvent('');
    setLastPayload('');
    try {
      // Use .env-provided values
      const sid = String(ENV_SID || '').trim();
      const tok = String(ENV_TOK || '').trim();
      const url = String(ENV_WS || '').trim();
      const u = normalizeWs(url) || adaptWsUrl(url).replace(/\/$/, '');
      setSessionId(sid);
      setToken(tok);
      setWsUrl(u);

      setWsState('connecting');
      const ws = new WebSocket(u);
      wsRef.current = ws;

      ws.onopen = () => {
        setWsState('open');
        setLastEvent('ws:open');
        setCloseInfo('');
        // Identify as phone
        const hello = { type: 'hello', s: sid, t: tok, r: 'phone' };
        ws.send(JSON.stringify(hello));
        // Start periodic heartbeats (every 20s)
        hbRef.current = setInterval(() => {
          try { ws.send(JSON.stringify({ type: 'hb' })); } catch {}
        }, 20000);
      };

      ws.onmessage = (e) => {
        // Default: do not change lastPayload unless we have a meaningful frame
        try {
          const obj = JSON.parse(String(e.data));
          if (obj && obj.type) setLastEvent(`ws:message:${obj.type}`);
          if (obj && obj.type === 'frame' && obj.frame && obj.b64 === false) {
            // Forwarded app frame from the other role
            try {
              const inner = JSON.parse(String(obj.frame));
              // Update ack if present
              if (inner && inner.type === 'ack') {
                setLastAck(inner.text ? String(inner.text) : JSON.stringify(inner));
              }
              setLastPayload(typeof inner === 'string' ? inner : JSON.stringify(inner));
            } catch {
              // Not JSON; show raw
              setLastPayload(String(obj.frame));
            }
          } else if (obj && obj.type === 'hb-ack') {
            // Ignore heartbeats for payload; keep UI clean
          } else {
            // For other control messages, clear payload to avoid showing stale data
            setLastPayload('');
          }
        } catch {
          // Non-JSON text message; treat as payload
          setLastEvent('ws:message:text');
          setLastPayload(String(e.data));
        }
      };

      ws.onerror = (e: any) => {
        setWsState('error');
        setLastEvent('ws:error');
        setCloseInfo(String(e?.message || ''));
      };

      ws.onclose = (e: any) => {
        setWsState('closed');
        setLastEvent('ws:close');
        if (e && (e.code || e.reason)) {
          setCloseInfo(`code=${e.code || ''} reason=${e.reason || ''}`);
        }
        if (hbRef.current) { clearInterval(hbRef.current); hbRef.current = null; }
      };
    } catch (e) {
      setWsState('error');
      setLastEvent('register:error');
      setLastPayload(String(e));
    }
  };

  // Auto-connect once health is connected (only once per mount)
  const autoConnectedRef = useRef(false);
  useEffect(() => {
    if (status === 'connected' && !autoConnectedRef.current) {
      autoConnectedRef.current = true;
      connect();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);

  const sendNote = () => {
    if (!wsRef.current || wsState !== 'open') return;
    const msg = (input || '').trim();
    setInput(''); // clear the input immediately
    const payload = { type: 'note', id: 'demo-p1', text: msg || 'hello-from-phone' };
    try {
      wsRef.current.send(JSON.stringify(payload));
      setLastEvent('sent:note');
      // Clear display fields so we don't show stale payload/ack until the relay/workstation responds
      setLastPayload('');
      // Do not clear lastAck here; keep last ack visible until a new one arrives
    } catch (e) {
      setLastEvent('send:error');
      setLastPayload(String(e));
    }
  };

  const pillBg = status === 'connected' ? colors.good : status === 'disconnected' ? colors.bad : colors.dim;
  const subtitle = lastCheckedAt
    ? `Last checked ${lastCheckedAt.toLocaleTimeString()}${latencyMs != null ? ` • ${latencyMs} ms` : ''}`
    : 'Checking...';

  return (
    <SafeAreaProvider>
    <SafeAreaView style={[styles.container, { backgroundColor: colors.bg }]}> 
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <Text style={[styles.title, { color: colors.fg }]}>VoiceRelay</Text>

      <View style={[styles.pill, { backgroundColor: pillBg }]}> 
        <Text style={styles.pillText}>
          {status === 'connected' ? 'Connected' : status === 'disconnected' ? 'Disconnected' : 'Checking...'}
        </Text>
      </View>
      <Text style={[styles.caption, { color: colors.dim }]}>{subtitle}</Text>

      {status !== 'connected' ? (
        <View style={[styles.hintBox, { borderColor: colors.dim }]}> 
          <Text style={[styles.hintText, { color: colors.fg }]}>Start relay server:</Text>
          <Text style={[styles.hintMono, { color: colors.fg }]}>cd relay/server</Text>
          <Text style={[styles.hintMono, { color: colors.fg }]}>cargo run --release --bin relay-server</Text>
          <Text style={[styles.hintText, { color: colors.dim, marginTop: 6 }]}>Health: {RELAY_HEALTH_URL ?? 'configure RELAY_WS_URL in .env'}</Text>
          <Text style={[styles.hintText, { color: colors.dim, marginTop: 6 }]}>sid/tok from .env</Text>
          <Text style={[styles.hintText, { color: colors.dim, marginTop: 6 }]}>Env WS: {ENV_WS ? String(ENV_WS) : 'missing'}</Text>
          <Text style={[styles.hintText, { color: colors.dim }]}>Env SID: {ENV_SID ? String(ENV_SID) : 'missing'}</Text>
          <Text style={[styles.hintText, { color: colors.dim }]}>Env TOK: {ENV_TOK ? String(ENV_TOK) : 'missing'}</Text>
        </View>
      ) : null}

      <View style={{ height: 12 }} />
      <View style={styles.rowWrap}>
        <TextInput
          value={input}
          onChangeText={setInput}
          placeholder="Type a message to send"
          placeholderTextColor={colors.dim}
          style={[styles.input, { color: colors.fg, borderColor: colors.dim, backgroundColor: isDarkMode ? '#111' : '#f7f7f7' }]}
        />
        <Pressable onPress={sendNote} disabled={wsState !== 'open'} style={[styles.btn, { backgroundColor: wsState === 'open' ? '#2563eb' : '#9ca3af' }]}>
          <Text style={styles.btnText}>Send</Text>
        </Pressable>
      </View>
      {lastAck ? <Text style={[styles.caption, { color: colors.dim, marginTop: 8 }]}>Ack: {lastAck}</Text> : null}

      <Pressable onPress={() => setShowDetails((v) => !v)} style={[styles.linkBtn]}>
        <Text style={[styles.linkBtnText, { color: '#2563eb' }]}>{showDetails ? 'Hide details' : 'Show details'}</Text>
      </Pressable>

      {showDetails ? (
        <View style={styles.detailsBox}>
          <Text style={[styles.sectionTitle, { color: colors.fg }]}>Debug</Text>
          <Text style={[styles.caption, { color: colors.dim }]}>State: {wsState}</Text>
          {wsUrl ? <Text style={[styles.caption, { color: colors.dim }]}>WS: {wsUrl}</Text> : null}
          {sessionId ? <Text style={[styles.caption, { color: colors.dim }]}>sid: {sessionId}</Text> : null}
          {token ? <Text style={[styles.caption, { color: colors.dim }]}>tok: {token}</Text> : null}
          {lastEvent ? <Text style={[styles.caption, { color: colors.dim }]}>Last: {lastEvent}</Text> : null}
          {closeInfo ? <Text style={[styles.caption, { color: colors.dim }]}>Close: {closeInfo}</Text> : null}
          {lastPayload ? <Text style={[styles.caption, { color: colors.dim }]} numberOfLines={3}>Payload: {lastPayload}</Text> : null}

          <View style={styles.row}>
            <Pressable onPress={connect} style={[styles.btn, { backgroundColor: '#2563eb' }]}>
              <Text style={styles.btnText}>Connect</Text>
            </Pressable>
            <Pressable onPress={disconnect} style={[styles.btn, { backgroundColor: '#6b7280' }]}>
              <Text style={styles.btnText}>Disconnect</Text>
            </Pressable>
            <Pressable
              onPress={() => {
                if (wsRef.current && wsState === 'open') {
                  try { wsRef.current.send('hi-from-phone'); setLastEvent('sent:text'); } catch {}
                }
              }}
              style={[styles.btn, { backgroundColor: '#059669' }]}
            >
              <Text style={styles.btnText}>Send Test</Text>
            </Pressable>
          </View>
        </View>
      ) : null}
    </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginTop: 8,
  },
  textSmall: {
    fontSize: 18,
    fontWeight: '600',
  },
  caption: {
    fontSize: 12,
    marginTop: 8,
  },
  pill: {
    marginTop: 16,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 999,
  },
  pillText: {
    color: '#fff',
    fontWeight: '700',
  },
  hintBox: {
    marginTop: 12,
    borderWidth: 1,
    borderRadius: 8,
    padding: 12,
    width: '90%',
  },
  hintText: {
    fontSize: 12,
  },
  hintMono: {
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }),
    fontSize: 12,
  },
  row: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 12,
  },
  rowWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 8,
    paddingHorizontal: 12,
    width: '100%',
  },
  input: {
    flex: 1,
    height: 40,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
  },
  btn: {
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 6,
  },
  btnText: {
    color: '#fff',
    fontWeight: '700',
  },
  linkBtn: {
    marginTop: 12,
  },
  linkBtnText: {
    fontWeight: '700',
  },
  detailsBox: {
    marginTop: 8,
    width: '90%',
  },
});

export default App;
