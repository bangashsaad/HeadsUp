import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import Svg, { Circle } from 'react-native-svg';
import { useTheme } from '../theme';

// Live countdown derived from the server's absolute `deadline` and `serverNow`
// (both ISO8601). We align the deadline to the local clock once (skew), then
// tick locally — and drain a circular ring that goes red in the final seconds.
const SIZE = 46;
const STROKE = 4;
const R = (SIZE - STROKE) / 2;
const CIRC = 2 * Math.PI * R;

export default function PickClock({ deadline, serverNow }) {
  const { colors } = useTheme();
  const [ms, setMs] = useState(0);
  const totalRef = useRef(1);

  useEffect(() => {
    if (!deadline || !serverNow) {
      setMs(0);
      totalRef.current = 1;
      return;
    }

    const skew = Date.now() - new Date(serverNow).getTime();
    const target = new Date(deadline).getTime() + skew;
    totalRef.current = Math.max(target - Date.now(), 1);
    const tick = () => setMs(Math.max(0, target - Date.now()));

    tick();
    const iv = setInterval(tick, 100);
    return () => clearInterval(iv);
  }, [deadline, serverNow]);

  const secs = Math.ceil(ms / 1000);
  const mm = Math.floor(secs / 60);
  const ss = secs % 60;
  const label = secs >= 60 ? `${mm}:${String(ss).padStart(2, '0')}` : `${secs}`;
  const low = secs <= 10;
  const frac = Math.max(0, Math.min(1, ms / totalRef.current));
  const ringColor = low ? colors.danger : colors.accent;

  return (
    <View style={styles.wrap}>
      <Svg width={SIZE} height={SIZE} style={StyleSheet.absoluteFill}>
        <Circle cx={SIZE / 2} cy={SIZE / 2} r={R} stroke={colors.border} strokeWidth={STROKE} fill="none" />
        <Circle
          cx={SIZE / 2}
          cy={SIZE / 2}
          r={R}
          stroke={ringColor}
          strokeWidth={STROKE}
          fill="none"
          strokeDasharray={CIRC}
          strokeDashoffset={CIRC * (1 - frac)}
          strokeLinecap="round"
          transform={`rotate(-90 ${SIZE / 2} ${SIZE / 2})`}
        />
      </Svg>
      <Text style={{ color: low ? colors.danger : colors.text, fontSize: secs >= 60 ? 13 : 15, fontWeight: '800', fontVariant: ['tabular-nums'] }}>
        {label}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { width: SIZE, height: SIZE, alignItems: 'center', justifyContent: 'center' },
});
