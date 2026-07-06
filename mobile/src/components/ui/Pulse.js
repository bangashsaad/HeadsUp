import { useEffect, useRef } from 'react';
import { Animated, View } from 'react-native';

// A soft expanding halo behind its children — the design's pulsing CTA ring.
export default function Pulse({ color = 'rgba(200,255,46,0.35)', borderRadius = 999, disabled = false, children, style }) {
  const v = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (disabled) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(v, { toValue: 1, duration: 1000, useNativeDriver: true }),
        Animated.timing(v, { toValue: 0, duration: 1000, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [v, disabled]);

  return (
    <View style={style}>
      {!disabled && (
        <Animated.View
          pointerEvents="none"
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            borderRadius,
            backgroundColor: color,
            opacity: v.interpolate({ inputRange: [0, 1], outputRange: [0, 0.55] }),
            transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 1.12] }) }],
          }}
        />
      )}
      {children}
    </View>
  );
}
