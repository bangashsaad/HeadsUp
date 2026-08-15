# Design tokens + UI kit — the iPhone app's full design system

Every screen file in this folder already carries a summary of this. Paste
this full version only when a redesign needs to touch the primitives
themselves (buttons, cards, badges, type).

## `src/theme.js` (complete)

```jsx
import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { Appearance, StyleSheet } from 'react-native';
import * as SecureStore from 'expo-secure-store';

// ---------------------------------------------------------------------------
// Tokens that don't change with light/dark.
// ---------------------------------------------------------------------------
export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 };
export const radius = { sm: 8, md: 12, lg: 16, xl: 20, pill: 999 };
export const font = {
  caption: 12,
  small: 13,
  body: 15,
  bodyLg: 16,
  subtitle: 17,
  title: 22,
  titleLg: 28,
  hero: 34,
};
export const shadow = {
  sm: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.16, shadowRadius: 6, elevation: 2 },
  md: { shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.2, shadowRadius: 12, elevation: 5 },
  lg: { shadowColor: '#000', shadowOffset: { width: 0, height: 8 }, shadowOpacity: 0.26, shadowRadius: 20, elevation: 10 },
};

// ---------------------------------------------------------------------------
// Typeface tokens ("Reimagined" design language). Each entry is a loaded
// expo-google-fonts face; when you set one as fontFamily, do NOT also set
// fontWeight (the weight is baked into the face name).
//   display   – Archivo Black energy, italic: wordmark, YOU WIN., ghost VS
//   hero      – Barlow Condensed 800 italic: scores, section titles, buttons
//   body*     – Archivo: running text and labels
// ---------------------------------------------------------------------------
export const fonts = {
  display: 'Archivo_900Black_Italic',
  displayUpright: 'Archivo_900Black',
  hero: 'BarlowCondensed_800ExtraBold_Italic',
  heroUpright: 'BarlowCondensed_800ExtraBold',
  condBold: 'BarlowCondensed_700Bold',
  condBoldItalic: 'BarlowCondensed_700Bold_Italic',
  condSemi: 'BarlowCondensed_600SemiBold',
  condMedium: 'BarlowCondensed_500Medium',
  body: 'Archivo_400Regular',
  bodyMedium: 'Archivo_500Medium',
  bodySemi: 'Archivo_600SemiBold',
  bodyBold: 'Archivo_700Bold',
  bodyExtra: 'Archivo_800ExtraBold',
  bodyBlack: 'Archivo_900Black',
};

// hex (#RRGGBB) -> rgba() string. The JS stand-in for CSS color-mix().
export function withAlpha(hex, alpha) {
  const h = hex.replace('#', '');
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

// ---------------------------------------------------------------------------
// Palettes. `onAccent` is the text/icon color that sits ON the accent (so the
// primary button stays legible: near-black text on lime).
// ---------------------------------------------------------------------------
const DARK = {
  bg: '#0A0B10',
  bgElevated: '#0D0F16',
  card: '#12141D',
  cardElevated: '#191C28',
  border: '#252A3A',
  borderSubtle: '#1A1E2B',
  text: '#F4F5F7',
  textDim: '#B9BECF',
  textFaint: '#3A4157',
  muted: '#8B91A7',
  placeholder: '#565D73',
  accent: '#C8FF2E',
  onAccent: '#0A0B10',
  accentSoft: 'rgba(200,255,46,0.10)',
  accentBorder: 'rgba(200,255,46,0.45)',
  danger: '#FF4557',
  dangerSoft: 'rgba(255,69,87,0.15)',
  dangerBorder: 'rgba(255,69,87,0.50)',
  warning: '#FFB021',
  warningSoft: 'rgba(255,176,33,0.14)',
  warningBorder: 'rgba(255,176,33,0.40)',
  info: '#9F8BFF',
  infoSoft: 'rgba(124,92,255,0.15)',
  infoBorder: 'rgba(124,92,255,0.45)',
  // Extended "Reimagined" family
  purple: '#7C5CFF',
  purpleText: '#9F8BFF',
  purpleSoft: 'rgba(124,92,255,0.15)',
  purpleBorder: 'rgba(124,92,255,0.45)',
  cyan: '#22E5FF',
  pink: '#FF4D8D',
  green: '#39D98A',
  orange: '#FF7A1A',
  gold: '#FFB021',
  silver: '#B9BECF',
  bronze: '#C97C3D',
};

const LIGHT = {
  bg: '#F4F5F8',
  bgElevated: '#ECEEF4',
  card: '#FFFFFF',
  cardElevated: '#EEF1F6', // bands/chips need to recess on white cards
  border: '#DCE0EA',
  borderSubtle: '#E8EBF2',
  text: '#12141D',
  textDim: '#3A4157',
  textFaint: '#C3C9D6',
  muted: '#565D73',
  placeholder: '#8B91A7',
  accent: '#65A30D',
  onAccent: '#FFFFFF',
  accentSoft: 'rgba(101,163,13,0.10)',
  accentBorder: 'rgba(101,163,13,0.32)',
  danger: '#E11D48',
  dangerSoft: 'rgba(225,29,72,0.08)',
  dangerBorder: 'rgba(225,29,72,0.28)',
  warning: '#C77700',
  warningSoft: 'rgba(199,119,0,0.10)',
  warningBorder: 'rgba(199,119,0,0.30)',
  info: '#6D4AFF',
  infoSoft: 'rgba(109,74,255,0.08)',
  infoBorder: 'rgba(109,74,255,0.28)',
  purple: '#6D4AFF',
  purpleText: '#6D4AFF',
  purpleSoft: 'rgba(109,74,255,0.08)',
  purpleBorder: 'rgba(109,74,255,0.28)',
  cyan: '#0891B2',
  pink: '#DB2777',
  green: '#0E9F6E',
  orange: '#EA580C',
  gold: '#B45309',
  silver: '#64748B',
  bronze: '#A16207',
};

export const PALETTES = { dark: DARK, light: LIGHT };

// Semantic tone -> {bg, text, border} for badges/pills/banners.
export function makeTones(c) {
  return {
    neutral: { bg: c.card, text: c.muted, border: c.border },
    accent: { bg: c.accentSoft, text: c.accent, border: c.accentBorder },
    danger: { bg: c.dangerSoft, text: c.danger, border: c.dangerBorder },
    warning: { bg: c.warningSoft, text: c.warning, border: c.warningBorder },
    info: { bg: c.infoSoft, text: c.info, border: c.infoBorder },
  };
}

// Map a duel status string to a tone name.
export function statusTone(status) {
  switch (status) {
    case 'accepted':
    case 'drafted':
    case 'settled':
      return 'accent';
    case 'drafting':
      return 'danger'; // live = red, per the Reimagined language
    case 'pending':
    case 'countered':
      return 'info';
    case 'declined':
    case 'cancelled':
      return 'danger';
    default:
      return 'neutral';
  }
}

// Deterministic avatar tint from a name (mode-independent).
const AVATAR_TINTS = ['#FF4D8D', '#22E5FF', '#39D98A', '#FFB021', '#7C5CFF', '#5CA8FF', '#FF7A1A'];
export function avatarColor(seed = '') {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return AVATAR_TINTS[h % AVATAR_TINTS.length];
}

// ---------------------------------------------------------------------------
// Theme context: a persisted preference ('system' | 'light' | 'dark') resolved
// to an active scheme, plus the matching palette + tones.
// ---------------------------------------------------------------------------
const MODE_KEY = 'theme_mode';
const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [mode, setModeState] = useState('dark'); // persisted preference
  const [systemScheme, setSystemScheme] = useState(Appearance.getColorScheme() || 'dark');

  useEffect(() => {
    (async () => {
      try {
        const saved = await SecureStore.getItemAsync(MODE_KEY);
        if (saved === 'light' || saved === 'dark' || saved === 'system') setModeState(saved);
      } catch (_) {}
    })();
    const sub = Appearance.addChangeListener(({ colorScheme }) => setSystemScheme(colorScheme || 'dark'));
    return () => sub.remove();
  }, []);

  function setMode(next) {
    setModeState(next);
    SecureStore.setItemAsync(MODE_KEY, next).catch(() => {});
  }

  const scheme = mode === 'system' ? systemScheme : mode;
  const colors = PALETTES[scheme] || DARK;
  const value = useMemo(
    () => ({ mode, setMode, scheme, colors, tones: makeTones(colors) }),
    [mode, scheme, colors]
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  return useContext(ThemeContext) || { mode: 'dark', setMode: () => {}, scheme: 'dark', colors: DARK, tones: makeTones(DARK) };
}

// Build a StyleSheet from the active theme; memoized per palette.
// Usage: const styles = useThemedStyles((c, t) => StyleSheet.create({...}))
export function useThemedStyles(factory) {
  const { colors, tones } = useTheme();
  return useMemo(() => factory(colors, tones), [colors, tones, factory]);
}

// Themed react-navigation header options (re-themes when the palette changes).
export function useNavHeader() {
  const { colors } = useTheme();
  return {
    headerStyle: { backgroundColor: colors.bg },
    headerTintColor: colors.text,
    headerShadowVisible: false,
    headerTitleStyle: { fontFamily: fonts.heroUpright, fontSize: 18, letterSpacing: 0.5 },
    headerBackTitleVisible: false,
    contentStyle: { backgroundColor: colors.bg },
  };
}

// ---------------------------------------------------------------------------
// Backward-compatible static exports (dark). Anything not yet converted to
// useTheme() keeps rendering against the dark palette and never crashes.
// ---------------------------------------------------------------------------
export const colors = DARK;
export const tones = makeTones(DARK);

export const navHeader = {
  headerStyle: { backgroundColor: DARK.bg },
  headerTintColor: DARK.text,
  headerShadowVisible: false,
  headerTitleStyle: { fontFamily: fonts.heroUpright, fontSize: 18, letterSpacing: 0.5 },
};

export const authStyles = StyleSheet.create({
  container: { flex: 1, backgroundColor: DARK.bg, justifyContent: 'center', padding: 24 },
  title: { color: DARK.text, fontSize: 30, fontWeight: '800', textAlign: 'center' },
  subtitle: { color: DARK.muted, fontSize: 15, textAlign: 'center', marginTop: 6, marginBottom: 28 },
  input: {
    backgroundColor: DARK.card,
    color: DARK.text,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: DARK.border,
  },
  button: { backgroundColor: DARK.accent, borderRadius: 12, paddingVertical: 16, alignItems: 'center', marginTop: 8 },
  buttonText: { color: DARK.onAccent, fontSize: 16, fontWeight: '700' },
  link: { color: DARK.accent, textAlign: 'center', marginTop: 18, fontSize: 15 },
  error: { color: DARK.danger, textAlign: 'center', marginBottom: 14, fontSize: 14 },
});
```

## The UI kit (`src/components/ui/`)

### `Avatar.js`

```jsx
import { View, Text } from 'react-native';
import { avatarColor, fonts } from '../../theme';

// Initials tile with a stable per-name tint. Rounded square ("squircle"), per
// the Reimagined language. (8-digit hex appends alpha.)
export default function Avatar({ name = '', size = 44, round = false, style }) {
  const initials =
    name
      .trim()
      .split(/\s+/)
      .map((w) => w[0])
      .slice(0, 2)
      .join('')
      .toUpperCase() || '?';
  const tint = avatarColor(name);

  return (
    <View
      style={[
        {
          width: size,
          height: size,
          borderRadius: round ? size / 2 : Math.round(size * 0.32),
          backgroundColor: tint + '22',
          borderWidth: 1.5,
          borderColor: tint + '66',
          alignItems: 'center',
          justifyContent: 'center',
        },
        style,
      ]}
    >
      <Text style={{ color: tint, fontFamily: fonts.bodyExtra, fontSize: size * 0.38 }}>{initials}</Text>
    </View>
  );
}
```

### `Badge.js`

```jsx
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
```

### `BlinkDot.js`

```jsx
import { useEffect, useRef } from 'react';
import { Animated } from 'react-native';

// The little live dot. blink=false renders it steady.
export default function BlinkDot({ color = '#FF4557', size = 6, blink = true, period = 1100, style }) {
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (!blink) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.25, duration: period / 2, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 1, duration: period / 2, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [opacity, blink, period]);

  return (
    <Animated.View
      style={[{ width: size, height: size, borderRadius: size / 2, backgroundColor: color, opacity: blink ? opacity : 1 }, style]}
    />
  );
}
```

### `Button.js`

```jsx
import { Pressable, Text, ActivityIndicator, View, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { impact } from '../../haptics';
import { useTheme, radius, shadow, fonts } from '../../theme';

// Condensed-italic pill buttons — the Reimagined CTA voice (ENTER ROOM →).
const SIZES = {
  sm: { py: 8, px: 15, font: 14, icon: 15 },
  md: { py: 13, px: 20, font: 16, icon: 18 },
  lg: { py: 15, px: 24, font: 18, icon: 20 },
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
  const { colors } = useTheme();
  const VARIANTS = {
    primary: { bg: colors.accent, fg: colors.onAccent, border: 'transparent' },
    outline: { bg: 'transparent', fg: colors.text, border: colors.border },
    danger: { bg: colors.dangerSoft, fg: colors.danger, border: colors.dangerBorder },
    ghost: { bg: 'transparent', fg: colors.muted, border: 'transparent' },
  };
  const v = VARIANTS[variant] || VARIANTS.primary;
  const s = SIZES[size] || SIZES.md;
  const isDisabled = disabled || loading;

  function handlePress(e) {
    if (isDisabled) return;
    if (haptic) impact();
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
        pressed && !isDisabled && { transform: [{ scale: 0.97 }], opacity: 0.92 },
        isDisabled && { opacity: 0.45 },
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={v.fg} />
      ) : (
        <View style={styles.row}>
          {icon && <Ionicons name={icon} size={s.icon} color={v.fg} style={{ marginRight: 8 }} />}
          <Text
            style={{
              color: v.fg,
              fontSize: s.font,
              fontFamily: fonts.hero,
              letterSpacing: 1.2,
              textTransform: 'uppercase',
            }}
          >
            {title}
          </Text>
          {iconRight && <Ionicons name={iconRight} size={s.icon} color={v.fg} style={{ marginLeft: 8 }} />}
        </View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: { borderRadius: radius.pill, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
});
```

### `Card.js`

```jsx
import { View, Pressable } from 'react-native';
import { useTheme, radius, spacing, shadow } from '../../theme';

// A surface with depth — border + soft shadow. Pass onPress to make it tappable.
export default function Card({ children, onPress, style, padded = true, elevated = false, ...rest }) {
  const { colors } = useTheme();
  const base = [
    {
      backgroundColor: elevated ? colors.cardElevated : colors.card,
      borderRadius: radius.lg,
      borderWidth: 1,
      borderColor: colors.border,
      padding: padded ? spacing.lg : 0,
    },
    shadow.sm,
    style,
  ];

  if (onPress) {
    return (
      <Pressable
        onPress={onPress}
        style={({ pressed }) => [...base, pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] }]}
        {...rest}
      >
        {children}
      </Pressable>
    );
  }

  return (
    <View style={base} {...rest}>
      {children}
    </View>
  );
}
```

### `Chip.js`

```jsx
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
```

### `EmptyState.js`

```jsx
import { View, Text } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, spacing, font } from '../../theme';

// Friendly centered placeholder: an icon coin, a title, a subtitle, and an
// optional action node (e.g. a Button).
export default function EmptyState({ icon = 'sparkles-outline', title, subtitle, action, style }) {
  const { colors } = useTheme();
  return (
    <View style={[{ alignItems: 'center', justifyContent: 'center', paddingVertical: spacing.xxl, paddingHorizontal: spacing.xl }, style]}>
      <View
        style={{
          width: 64,
          height: 64,
          borderRadius: 32,
          backgroundColor: colors.card,
          alignItems: 'center',
          justifyContent: 'center',
          marginBottom: spacing.lg,
          borderWidth: 1,
          borderColor: colors.borderSubtle,
        }}
      >
        <Ionicons name={icon} size={30} color={colors.muted} />
      </View>
      {title ? <Text style={{ color: colors.text, fontSize: font.subtitle, fontWeight: '700', textAlign: 'center' }}>{title}</Text> : null}
      {subtitle ? (
        <Text style={{ color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: 6, lineHeight: 21 }}>{subtitle}</Text>
      ) : null}
      {action ? <View style={{ marginTop: spacing.lg, alignSelf: 'stretch' }}>{action}</View> : null}
    </View>
  );
}
```

### `FadeIn.js`

```jsx
import { useEffect, useRef } from 'react';
import { Animated } from 'react-native';

// Fade + slide a list row in on mount, lightly staggered by its index.
export default function FadeIn({ children, index = 0, style }) {
  const v = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(v, {
      toValue: 1,
      duration: 280,
      delay: Math.min(index, 8) * 35,
      useNativeDriver: true,
    }).start();
  }, [v, index]);

  return (
    <Animated.View
      style={[{ opacity: v, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [8, 0] }) }] }, style]}
    >
      {children}
    </Animated.View>
  );
}
```

### `Field.js`

```jsx
import { useState } from 'react';
import { View, Text, TextInput, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, radius, spacing, font } from '../../theme';

// Labeled text input with optional password show/hide, a valid ✓, and an error.
export default function Field({
  label,
  value,
  onChangeText,
  placeholder,
  secure = false,
  error,
  valid,
  keyboardType,
  autoCapitalize = 'none',
  autoFocus = false,
  style,
}) {
  const { colors } = useTheme();
  const [hidden, setHidden] = useState(secure);

  return (
    <View style={[{ marginBottom: spacing.md }, style]}>
      {label ? <Text style={{ color: colors.muted, fontSize: font.small, fontWeight: '700', marginBottom: 6 }}>{label}</Text> : null}
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          backgroundColor: colors.card,
          borderRadius: radius.md,
          borderWidth: 1,
          borderColor: error ? colors.dangerBorder : colors.border,
          paddingHorizontal: spacing.md,
        }}
      >
        <TextInput
          style={{ flex: 1, color: colors.text, fontSize: font.bodyLg, paddingVertical: 14 }}
          placeholder={placeholder}
          placeholderTextColor={colors.placeholder}
          value={value}
          onChangeText={onChangeText}
          secureTextEntry={hidden}
          keyboardType={keyboardType}
          autoCapitalize={autoCapitalize}
          autoCorrect={false}
          autoFocus={autoFocus}
        />
        {valid ? <Ionicons name="checkmark-circle" size={18} color={colors.accent} style={{ marginLeft: 6 }} /> : null}
        {secure ? (
          <Pressable onPress={() => setHidden((h) => !h)} hitSlop={8} style={{ marginLeft: 6 }}>
            <Ionicons name={hidden ? 'eye-outline' : 'eye-off-outline'} size={20} color={colors.placeholder} />
          </Pressable>
        ) : null}
      </View>
      {error ? <Text style={{ color: colors.danger, fontSize: font.small, marginTop: 6 }}>{error}</Text> : null}
    </View>
  );
}
```

### `GhostText.js`

```jsx
import Svg, { Text as SvgText } from 'react-native-svg';
import { fonts, useTheme, withAlpha } from '../../theme';

// Outline-only display text — the big translucent "VS" / pick-number watermarks.
// Rendered as stroked SVG text (RN has no text-stroke). Defaults to a faint
// stroke of the theme's text color, so it reads in light mode too.
export default function GhostText({
  children,
  size = 34,
  color,
  strokeWidth = 1.2,
  family = fonts.display,
  width,
  height,
  style,
}) {
  const { colors } = useTheme();
  const stroke = color || withAlpha(colors.text, 0.09);
  const label = String(children);
  const w = width ?? Math.ceil(size * Math.max(1, label.length) * 0.78);
  const h = height ?? Math.ceil(size * 1.25);
  return (
    <Svg width={w} height={h} style={style} pointerEvents="none">
      <SvgText
        x={w / 2}
        y={h * 0.8}
        fontSize={size}
        fontFamily={family}
        textAnchor="middle"
        fill="none"
        stroke={stroke}
        strokeWidth={strokeWidth}
      >
        {label}
      </SvgText>
    </Svg>
  );
}
```

### `Marquee.js`

```jsx
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
```

### `Pulse.js`

```jsx
import { useEffect, useRef } from 'react';
import { Animated, View } from 'react-native';

// A soft expanding halo behind its children — the design's pulsing CTA ring.
export default function Pulse({ color = 'rgba(200,255,46,0.35)', borderRadius = 999, disabled = false, children, style }) {
  const v = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (disabled) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(v, { toValue: 1, duration: 1000, useNativeDriver: true }),
        Animated.timing(v, { toValue: 0, duration: 1000, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [v, disabled]);

  return (
    <View style={style}>
      {!disabled && (
        <Animated.View
          pointerEvents="none"
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            borderRadius,
            backgroundColor: color,
            opacity: v.interpolate({ inputRange: [0, 1], outputRange: [0, 0.55] }),
            transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 1.12] }) }],
          }}
        />
      )}
      {children}
    </View>
  );
}
```

### `Screen.js`

```jsx
import { View, ScrollView, KeyboardAvoidingView, Platform, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme, spacing } from '../../theme';

// Page wrapper: themed bg, keyboard avoidance, and an optional scroll view with
// pull-to-refresh. No safe-area insets by default (the header owns the top, the
// tab bar owns the bottom).
export default function Screen({
  children,
  scroll = false,
  padded = true,
  style,
  contentStyle,
  edges = [],
  refreshing,
  onRefresh,
}) {
  const { colors } = useTheme();
  const padStyle = padded ? { padding: spacing.lg } : null;

  const refreshControl =
    onRefresh != null ? (
      <RefreshControl refreshing={!!refreshing} onRefresh={onRefresh} tintColor={colors.muted} />
    ) : undefined;

  const inner = scroll ? (
    <ScrollView
      contentContainerStyle={[padStyle, contentStyle]}
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
      refreshControl={refreshControl}
    >
      {children}
    </ScrollView>
  ) : (
    <View style={[{ flex: 1 }, padStyle, contentStyle]}>{children}</View>
  );

  return (
    <SafeAreaView edges={edges} style={[{ flex: 1, backgroundColor: colors.bg }, style]}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        {inner}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
```

### `SearchInput.js`

```jsx
import { View, TextInput, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, radius, spacing, font } from '../../theme';

// Text field with a leading search icon and a clear (×) button.
export default function SearchInput({ value, onChangeText, placeholder = 'Search', style, autoFocus = false }) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        {
          flexDirection: 'row',
          alignItems: 'center',
          backgroundColor: colors.card,
          borderRadius: radius.md,
          borderWidth: 1,
          borderColor: colors.border,
          paddingHorizontal: spacing.md,
        },
        style,
      ]}
    >
      <Ionicons name="search" size={18} color={colors.placeholder} />
      <TextInput
        style={{ flex: 1, color: colors.text, fontSize: font.bodyLg, paddingVertical: 12, paddingHorizontal: spacing.sm }}
        placeholder={placeholder}
        placeholderTextColor={colors.placeholder}
        autoCapitalize="none"
        autoCorrect={false}
        value={value}
        onChangeText={onChangeText}
        autoFocus={autoFocus}
        returnKeyType="search"
      />
      {value ? (
        <Pressable onPress={() => onChangeText('')} hitSlop={8}>
          <Ionicons name="close-circle" size={18} color={colors.placeholder} />
        </Pressable>
      ) : null}
    </View>
  );
}
```

### `SectionHeader.js`

```jsx
import { View, Text } from 'react-native';
import { useTheme, fonts, spacing } from '../../theme';

// Condensed-italic section title, e.g. "YOUR MOVE", with an optional right hint
// ("3 PENDING"). Accepts a plain string child for back-compat.
export default function SectionHeader({ children, hint, style }) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        {
          flexDirection: 'row',
          alignItems: 'baseline',
          justifyContent: 'space-between',
          marginBottom: spacing.sm,
          marginTop: spacing.lg,
        },
        style,
      ]}
    >
      <Text
        style={{
          color: colors.text,
          fontFamily: fonts.hero,
          fontSize: 17,
          letterSpacing: 1,
          textTransform: 'uppercase',
        }}
      >
        {children}
      </Text>
      {hint ? (
        <Text style={{ color: colors.placeholder, fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 1, textTransform: 'uppercase' }}>
          {hint}
        </Text>
      ) : null}
    </View>
  );
}
```

### `Segmented.js`

```jsx
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
```

### `Skeleton.js`

```jsx
import { useEffect, useRef } from 'react';
import { Animated, View } from 'react-native';
import { useTheme, radius, spacing } from '../../theme';

// A single pulsing placeholder bar.
export function Skeleton({ width = '100%', height = 14, style, round = false }) {
  const { colors } = useTheme();
  const opacity = useRef(new Animated.Value(0.4)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 1, duration: 700, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.4, duration: 700, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [opacity]);

  return (
    <Animated.View
      style={[{ width, height, borderRadius: round ? height / 2 : radius.sm, backgroundColor: colors.card, opacity }, style]}
    />
  );
}

// An avatar + two-line text row, matching a typical list item.
export function SkeletonRow() {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md }}>
      <Skeleton width={44} height={44} round />
      <View style={{ marginLeft: spacing.md, flex: 1 }}>
        <Skeleton width="55%" height={14} />
        <Skeleton width="35%" height={11} style={{ marginTop: 8 }} />
      </View>
    </View>
  );
}

export function SkeletonList({ count = 5 }) {
  return (
    <View>
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonRow key={i} />
      ))}
    </View>
  );
}
```

### `StatTile.js`

```jsx
import { View, Text } from 'react-native';
import { useTheme, fonts, radius } from '../../theme';

// One tile of the 4-up stat grid: big condensed-italic value over a tiny kicker.
export default function StatTile({ value, label, color, style }) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        {
          flex: 1,
          backgroundColor: colors.card,
          borderWidth: 1,
          borderColor: colors.border,
          borderRadius: radius.md,
          paddingVertical: 10,
          alignItems: 'center',
        },
        style,
      ]}
    >
      <Text style={{ fontFamily: fonts.hero, fontSize: 24, color: color || colors.text }}>{value}</Text>
      <Text
        style={{
          fontSize: 8.5,
          fontFamily: fonts.bodyExtra,
          letterSpacing: 1.5,
          color: colors.placeholder,
          marginTop: 2,
          textTransform: 'uppercase',
        }}
      >
        {label}
      </Text>
    </View>
  );
}
```

### `Type.js`

```jsx
import { Text } from 'react-native';
import { useTheme, fonts } from '../../theme';

// The three voices of the Reimagined type system.

// Tiny 800-weight uppercase tracking label: "SEASON RECORD", "PICK 3 OF 10".
export function Kicker({ children, color, size = 10, tracking = 2, style, ...rest }) {
  const { colors } = useTheme();
  return (
    <Text
      style={[
        { color: color || colors.placeholder, fontSize: size, fontFamily: fonts.bodyExtra, letterSpacing: tracking, textTransform: 'uppercase' },
        style,
      ]}
      {...rest}
    >
      {children}
    </Text>
  );
}

// Barlow Condensed 800 italic display: scores, titles, "YOU'RE ON THE CLOCK".
export function CondTitle({ children, color, size = 22, italic = true, style, ...rest }) {
  const { colors } = useTheme();
  return (
    <Text
      style={[
        {
          color: color || colors.text,
          fontSize: size,
          fontFamily: italic ? fonts.hero : fonts.heroUpright,
          letterSpacing: 0.5,
        },
        style,
      ]}
      {...rest}
    >
      {children}
    </Text>
  );
}

// Archivo Black energy (900 italic): "YOU WIN.", "LOCKED IN.", the wordmark.
export function DisplayTitle({ children, color, size = 34, style, ...rest }) {
  const { colors } = useTheme();
  return (
    <Text style={[{ color: color || colors.text, fontSize: size, fontFamily: fonts.display, letterSpacing: -0.5 }, style]} {...rest}>
      {children}
    </Text>
  );
}
```

### `index.js`

```jsx
export { default as Button } from './Button';
export { default as Card } from './Card';
export { default as Screen } from './Screen';
export { default as Badge } from './Badge';
export { default as Avatar } from './Avatar';
export { default as EmptyState } from './EmptyState';
export { default as SectionHeader } from './SectionHeader';
export { default as SearchInput } from './SearchInput';
export { default as Field } from './Field';
export { default as Chip } from './Chip';
export { default as FadeIn } from './FadeIn';
export { Skeleton, SkeletonRow, SkeletonList } from './Skeleton';
export { default as BlinkDot } from './BlinkDot';
export { default as GhostText } from './GhostText';
export { default as Pulse } from './Pulse';
export { default as Marquee } from './Marquee';
export { default as StatTile } from './StatTile';
export { default as Segmented } from './Segmented';
export { Kicker, CondTitle, DisplayTitle } from './Type';
```
