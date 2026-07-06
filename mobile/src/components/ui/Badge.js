import { View, Text } from 'react-native';
import { useTheme, radius, fonts } from '../../theme';
import BlinkDot from './BlinkDot';

// Small uppercase status pill. `tone` is one of the keys in theme `tones`.
// `dot` shows a leading dot; `blink` makes it pulse (live things blink).
export default function Badge({ label, tone = 'neutral', style, dot = false, blink = false }) {
  const { tones } = useTheme();
  const t = tones[tone] || tones.neutral;
  return (
    <View
      style={[
        {
          backgroundColor: t.bg,
          borderColor: t.border,
          borderWidth: 1,
          borderRadius: radius.pill,
          paddingVertical: 3.5,
          paddingHorizontal: 9,
          alignSelf: 'flex-start',
          flexDirection: 'row',
          alignItems: 'center',
        },
        style,
      ]}
    >
      {(dot || blink) && <BlinkDot color={t.text} size={6} blink={blink} style={{ marginRight: 6 }} />}
      <Text style={{ color: t.text, fontSize: 10, fontFamily: fonts.bodyExtra, textTransform: 'uppercase', letterSpacing: 1.2 }}>
        {label}
      </Text>
    </View>
  );
}
