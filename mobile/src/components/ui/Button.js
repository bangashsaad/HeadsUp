import { Pressable, Text, ActivityIndicator, View, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { colors, radius, shadow } from '../../theme';

// One button to rule them all: variants, sizes, loading, leading/trailing
// icons, a subtle press animation, and a light haptic tap.
const VARIANTS = {
  primary: { bg: colors.accent, fg: colors.bg, border: 'transparent' },
  outline: { bg: 'transparent', fg: colors.text, border: colors.border },
  danger: { bg: colors.dangerSoft, fg: colors.danger, border: 'rgba(248,113,113,0.4)' },
  ghost: { bg: 'transparent', fg: colors.muted, border: 'transparent' },
};

const SIZES = {
  sm: { py: 9, px: 14, font: 14, icon: 16 },
  md: { py: 14, px: 18, font: 16, icon: 18 },
  lg: { py: 16, px: 20, font: 17, icon: 20 },
};

export default function Button({
  title,
  onPress,
  variant = 'primary',
  size = 'md',
  loading = false,
  disabled = false,
  icon,
  iconRight,
  haptic = true,
  full = true,
  style,
}) {
  const v = VARIANTS[variant] || VARIANTS.primary;
  const s = SIZES[size] || SIZES.md;
  const isDisabled = disabled || loading;

  function handlePress(e) {
    if (isDisabled) return;
    if (haptic) Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
    onPress && onPress(e);
  }

  return (
    <Pressable
      onPress={handlePress}
      disabled={isDisabled}
      accessibilityRole="button"
      accessibilityState={{ disabled: isDisabled, busy: loading }}
      style={({ pressed }) => [
        styles.base,
        { backgroundColor: v.bg, borderColor: v.border, paddingVertical: s.py, paddingHorizontal: s.px },
        variant === 'primary' && !isDisabled && shadow.sm,
        full && { alignSelf: 'stretch' },
        pressed && !isDisabled && { transform: [{ scale: 0.985 }], opacity: 0.92 },
        isDisabled && { opacity: 0.45 },
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={v.fg} />
      ) : (
        <View style={styles.row}>
          {icon && <Ionicons name={icon} size={s.icon} color={v.fg} style={{ marginRight: 8 }} />}
          <Text style={{ color: v.fg, fontSize: s.font, fontWeight: '700' }}>{title}</Text>
          {iconRight && <Ionicons name={iconRight} size={s.icon} color={v.fg} style={{ marginLeft: 8 }} />}
        </View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: { borderRadius: radius.md, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
});
