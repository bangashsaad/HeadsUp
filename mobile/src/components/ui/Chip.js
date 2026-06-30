import { Pressable, Text } from 'react-native';
import * as Haptics from 'expo-haptics';
import { colors, radius, font } from '../../theme';

// A selectable pill (filters, toggles). Light selection haptic on tap.
export default function Chip({ label, active = false, onPress, style }) {
  return (
    <Pressable
      onPress={() => {
        Haptics.selectionAsync().catch(() => {});
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
      <Text style={{ color: active ? colors.bg : colors.muted, fontWeight: '700', fontSize: font.small }}>{label}</Text>
    </Pressable>
  );
}
