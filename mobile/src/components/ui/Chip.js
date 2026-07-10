import { Pressable, Text } from 'react-native';
import { selection } from '../../haptics';
import { useTheme, radius, fonts } from '../../theme';

// A selectable pill (filters, toggles). Light selection haptic on tap.
// Mirrors the Segmented recipe: center the label and let Barlow Condensed keep
// its NATURAL line height — forcing a lineHeight clips the glyphs on iOS.
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
          alignItems: 'center',
          justifyContent: 'center',
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
          // Belt & braces vs the squashed-line-box clipping (root cause is
          // flex shrink in the parent — see GamesScreen's day strip).
          lineHeight: 17,
          letterSpacing: 1,
        }}
      >
        {String(label).toUpperCase()}
      </Text>
    </Pressable>
  );
}
