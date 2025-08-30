/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { SafeAreaView, StatusBar, Text, useColorScheme, StyleSheet, View, Platform } from 'react-native';

type HealthStatus = 'checking' | 'connected' | 'disconnected';

const RELAY_PORT = 3001; // Default relay server port (see relay/server/README.md)
const RELAY_HOST = Platform.select({ ios: 'localhost', android: '10.0.2.2', default: 'localhost' });
const RELAY_HEALTH_URL = `http://${RELAY_HOST}:${RELAY_PORT}/health`;

function App() {
  const isDarkMode = useColorScheme() === 'dark';
  const [status, setStatus] = useState<HealthStatus>('checking');
  const [lastCheckedAt, setLastCheckedAt] = useState<Date | null>(null);
  const [latencyMs, setLatencyMs] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

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

  const pillBg = status === 'connected' ? colors.good : status === 'disconnected' ? colors.bad : colors.dim;
  const subtitle = lastCheckedAt
    ? `Last checked ${lastCheckedAt.toLocaleTimeString()}${latencyMs != null ? ` • ${latencyMs} ms` : ''}`
    : 'Checking...';

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.bg }]}> 
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <Text style={[styles.text, { color: colors.fg }]}>Yes hello i can update this in real time without rebuilding</Text>

      <View style={[styles.pill, { backgroundColor: pillBg }]}> 
        <Text style={styles.pillText}>
          {status === 'connected' ? 'Connected' : status === 'disconnected' ? 'Disconnected' : 'Checking...'}
        </Text>
      </View>
      <Text style={[styles.subText, { color: colors.dim }]}>{subtitle}</Text>
      <Text style={[styles.subText, { color: colors.dim, marginTop: 4 }]}>Health: {RELAY_HEALTH_URL}</Text>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  text: {
    fontSize: 24,
    fontWeight: '600',
  },
  subText: {
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
});

export default App;
