import { View, Text } from 'react-native';
import { tones, radius, font } from '../../theme';

// Small uppercase status pill. `tone` is one of the keys in theme `tones`.
export default function Badge({ label, tone = 'neutral', style, dot = false }) {
  const t = tones[tone] || tones.neutral;
  return (
    <View
      style={[
        {
          backgroundColor: t.bg,
          borderColor: t.border,
          borderWidth: 1,
          borderRadius: radius.pill,
          paddingVertical: 4,
          paddingHorizontal: 10,
          alignSelf: 'flex-start',
          flexDirection: 'row',
          alignItems: 'center',
        },
        style,
      ]}
    >
      {dot && (
        <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: t.text, marginRight: 6 }} />
      )}
      <Text style={{ color: t.text, fontSize: font.caption, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5 }}>
        {label}
      </Text>
    </View>
  );
}
