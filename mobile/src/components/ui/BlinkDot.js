import { useEffect, useRef } from 'react';
import { Animated } from 'react-native';

// The little live dot. blink=false renders it steady.
export default function BlinkDot({ color = '#FF4557', size = 6, blink = true, period = 1100, style }) {
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (!blink) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.25, duration: period / 2, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 1, duration: period / 2, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [opacity, blink, period]);

  return (
    <Animated.View
      style={[{ width: size, height: size, borderRadius: size / 2, backgroundColor: color, opacity: blink ? opacity : 1 }, style]}
    />
  );
}
