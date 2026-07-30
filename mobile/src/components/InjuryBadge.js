import { StyleSheet, Text, View } from 'react-native';
import { useTheme, fonts, withAlpha } from '../theme';

// OUT / IL-60 / GTD. Red means "will not play" — a guaranteed zero on a
// single-day slate. Amber means "might play".
//
// Renders nothing when there's no injury, so callers can drop it in
// unconditionally without a ternary at every call site.
export default function InjuryBadge({ injury, style }) {
  const { colors } = useTheme();
  if (!injury?.label) return null;

  const out = injury.status === 'out';
  const tint = out ? colors.danger : colors.gold;

  return (
    <View
      style={[
        styles.badge,
        { backgroundColor: withAlpha(tint, 0.15), borderColor: withAlpha(tint, 0.45) },
        style,
      ]}
    >
      <Text style={[styles.text, { color: tint }]}>{injury.label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: { paddingHorizontal: 5, paddingVertical: 1, borderRadius: 4, borderWidth: 1 },
  text: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
});
