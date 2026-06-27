import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

// Renders a live countdown derived from the server's absolute `deadline` and
// `serverNow` (both ISO8601). We align the server deadline to the local clock
// once (skew), then tick locally — no per-second server traffic.
export default function PickClock({ deadline, serverNow }) {
  const [remaining, setRemaining] = useState(0);

  useEffect(() => {
    if (!deadline || !serverNow) {
      setRemaining(0);
      return;
    }

    const skew = Date.now() - new Date(serverNow).getTime();
    const target = new Date(deadline).getTime() + skew;
    const tick = () => setRemaining(Math.max(0, Math.round((target - Date.now()) / 1000)));

    tick();
    const iv = setInterval(tick, 250);
    return () => clearInterval(iv);
  }, [deadline, serverNow]);

  const mm = Math.floor(remaining / 60);
  const ss = remaining % 60;
  const label = remaining >= 60 ? `${mm}:${String(ss).padStart(2, '0')}` : `${remaining}s`;
  const low = remaining <= 10;

  return (
    <View style={[styles.clock, low && styles.clockLow]}>
      <Text style={[styles.text, low && styles.textLow]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  clock: {
    paddingHorizontal: 16,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  clockLow: { borderColor: colors.danger, backgroundColor: '#3f1d1d' },
  text: { color: colors.text, fontSize: 18, fontWeight: '800', fontVariant: ['tabular-nums'] },
  textLow: { color: colors.danger },
});
