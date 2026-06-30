import { useEffect, useRef } from 'react';
import { Animated } from 'react-native';

// Fade + slide a list row in on mount, lightly staggered by its index.
export default function FadeIn({ children, index = 0, style }) {
  const v = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(v, {
      toValue: 1,
      duration: 280,
      delay: Math.min(index, 8) * 35,
      useNativeDriver: true,
    }).start();
  }, [v, index]);

  return (
    <Animated.View
      style={[{ opacity: v, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [8, 0] }) }] }, style]}
    >
      {children}
    </Animated.View>
  );
}
