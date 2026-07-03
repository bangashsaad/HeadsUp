import { useEffect, useRef } from 'react';
import { Animated, Dimensions, Easing, StyleSheet, View } from 'react-native';

const COLORS = ['#4ade80', '#fbbf24', '#3b82f6', '#ec4899', '#8b5cf6', '#f97316', '#22d3ee'];
const COUNT = 28;

// A one-shot confetti rain for the winner moment. Pure Animated (no deps, runs
// in Expo Go): strips and dots fall from above the screen with drift and spin,
// fading out near the bottom. Mount it over the screen; it ignores touches.
export default function ConfettiBurst({ duration = 2800 }) {
  const pieces = useRef(
    Array.from({ length: COUNT }, (_, i) => ({
      progress: new Animated.Value(0),
      x: Math.random(),
      drift: (Math.random() - 0.5) * 140,
      size: 7 + Math.random() * 6,
      color: COLORS[i % COLORS.length],
      delay: Math.random() * 600,
      spin: (Math.random() < 0.5 ? -1 : 1) * (360 + Math.round(Math.random() * 360)),
      strip: Math.random() < 0.6,
    }))
  ).current;

  useEffect(() => {
    Animated.parallel(
      pieces.map((p) =>
        Animated.timing(p.progress, {
          toValue: 1,
          duration,
          delay: p.delay,
          easing: Easing.in(Easing.quad),
          useNativeDriver: true,
        })
      )
    ).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const { width, height } = Dimensions.get('window');

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      {pieces.map((p, i) => (
        <Animated.View
          key={i}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: p.strip ? p.size * 0.55 : p.size,
            height: p.strip ? p.size * 1.7 : p.size,
            borderRadius: p.strip ? 1.5 : p.size / 2,
            backgroundColor: p.color,
            opacity: p.progress.interpolate({ inputRange: [0, 0.75, 1], outputRange: [1, 1, 0] }),
            transform: [
              { translateX: p.progress.interpolate({ inputRange: [0, 1], outputRange: [p.x * width, p.x * width + p.drift] }) },
              { translateY: p.progress.interpolate({ inputRange: [0, 1], outputRange: [-30, height + 30] }) },
              { rotate: p.progress.interpolate({ inputRange: [0, 1], outputRange: ['0deg', `${p.spin}deg`] }) },
            ],
          }}
        />
      ))}
    </View>
  );
}
