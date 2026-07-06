import { Pressable, Text } from 'react-native';
import { selection } from '../../haptics';
import { useTheme, radius, fonts } from '../../theme';

// A selectable pill (filters, toggles). Light selection haptic on tap.
export default function Chip({ label, active = false, onPress, style }) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={() => {
        selection();
        onPress && onPress();
      }}
      style={({ pressed }) => [
        {
          paddingHorizontal: 14,
          paddingVertical: 8,
          borderRadius: radius.md,
          borderWidth: 1,
          backgroundColor: active ? colors.accent : colors.card,
          borderColor: active ? colors.accent : colors.border,
        },
        pressed && { opacity: 0.8 },
        style,
      ]}
    >
      <Text
        numberOfLines={1}
        style={{
          color: active ? colors.onAccent : colors.muted,
          fontFamily: fonts.heroUpright,
          fontSize: 13,
          lineHeight: 17,
          letterSpacing: 1,
          textTransform: 'uppercase',
          includeFontPadding: false,
        }}
      >
        {label}
      </Text>
    </Pressable>
  );
}
