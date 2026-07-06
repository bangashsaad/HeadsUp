import { View, Text, Pressable } from 'react-native';
import { selection } from '../../haptics';
import { useTheme, fonts } from '../../theme';

// The ACTIVE | PAST switch: a recessed track with a lime active segment.
// options: [{ key, label, count }]
export default function Segmented({ options = [], value, onChange, style }) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        {
          flexDirection: 'row',
          gap: 6,
          backgroundColor: colors.card,
          borderWidth: 1,
          borderColor: colors.border,
          borderRadius: 11,
          padding: 4,
        },
        style,
      ]}
    >
      {options.map((opt) => {
        const active = opt.key === value;
        const fg = active ? colors.onAccent : colors.muted;
        return (
          <Pressable
            key={opt.key}
            onPress={() => {
              if (!active) {
                selection();
                onChange && onChange(opt.key);
              }
            }}
            style={{
              flex: 1,
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 6,
              paddingVertical: 8,
              borderRadius: 8,
              backgroundColor: active ? colors.accent : 'transparent',
            }}
          >
            <Text style={{ fontFamily: fonts.heroUpright, fontSize: 15, letterSpacing: 1, color: fg, textTransform: 'uppercase' }}>
              {opt.label}
            </Text>
            {opt.count != null && (
              <Text style={{ fontSize: 10, fontFamily: fonts.bodyBlack, color: fg, opacity: 0.7 }}>{opt.count}</Text>
            )}
          </Pressable>
        );
      })}
    </View>
  );
}
