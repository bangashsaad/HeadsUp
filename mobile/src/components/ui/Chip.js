import { Pressable, Text } from 'react-native';
import { selection } from '../../haptics';
import { useTheme, radius, font } from '../../theme';

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
          borderRadius: radius.pill,
          borderWidth: 1,
          backgroundColor: active ? colors.accent : colors.card,
          borderColor: active ? colors.accent : colors.border,
        },
        pressed && { opacity: 0.8 },
        style,
      ]}
    >
      <Text style={{ color: active ? colors.onAccent : colors.muted, fontWeight: '700', fontSize: font.small }}>{label}</Text>
    </Pressable>
  );
}
