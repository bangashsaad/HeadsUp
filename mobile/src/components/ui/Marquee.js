import { useEffect, useRef, useState } from 'react';
import { Animated, View } from 'react-native';

// Endless horizontal ticker: renders `children` twice and slides one copy's
// width, looping seamlessly. `speed` is px/second.
export default function Marquee({ children, speed = 36, gap = 26, style }) {
  const x = useRef(new Animated.Value(0)).current;
  const [w, setW] = useState(0);

  useEffect(() => {
    if (!w) return;
    x.setValue(0);
    const loop = Animated.loop(
      Animated.timing(x, {
        toValue: -w,
        duration: (w / speed) * 1000,
        useNativeDriver: true,
        easing: (t) => t, // linear
      })
    );
    loop.start();
    return () => loop.stop();
  }, [x, w, speed]);

  return (
    <View style={[{ overflow: 'hidden', flexDirection: 'row' }, style]}>
      <Animated.View style={{ flexDirection: 'row', transform: [{ translateX: x }] }}>
        <View
          style={{ flexDirection: 'row', alignItems: 'center', paddingRight: gap }}
          onLayout={(e) => setW(Math.ceil(e.nativeEvent.layout.width))}
        >
          {children}
        </View>
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingRight: gap }}>{children}</View>
      </Animated.View>
    </View>
  );
}
