import { useEffect, useRef, useState } from 'react';
import { Animated } from 'react-native';
import { useTheme, fonts } from '../theme';

// A live score that celebrates its own changes: when the value ticks up it
// pops (scale spring) and flashes lime before settling back to its color.
export default function ScoreFlash({ value, size = 42, color, style }) {
  const { colors } = useTheme();
  const scale = useRef(new Animated.Value(1)).current;
  const [flash, setFlash] = useState(false);
  const prev = useRef(value);

  useEffect(() => {
    if (prev.current !== value && prev.current != null && value != null) {
      setFlash(true);
      scale.setValue(1.26);
      Animated.spring(scale, { toValue: 1, friction: 4, tension: 90, useNativeDriver: true }).start();
      const t = setTimeout(() => setFlash(false), 850);
      prev.current = value;
      return () => clearTimeout(t);
    }
    prev.current = value;
  }, [value, scale]);

  return (
    <Animated.Text
      style={[
        {
          fontFamily: fonts.hero,
          fontSize: size,
          lineHeight: size + 2,
          color: flash ? colors.accent : color || colors.text,
          paddingRight: 4,
          transform: [{ scale }],
        },
        style,
      ]}
    >
      {value ?? '—'}
    </Animated.Text>
  );
}
