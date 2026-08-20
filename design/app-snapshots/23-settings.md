# Settings — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Theme (dark/light/system) and account controls.

## The app's design language (real tokens, from `src/theme.js`)

Dark palette (the shipped look): bg `#0A0B10`, elevated `#0D0F16`, card `#12141D`,
card-elevated `#191C28`, border `#252A3A`, subtle border `#1A1E2B`, text `#F4F5F7`,
dim `#B9BECF`, muted `#8B91A7`, placeholder `#565D73`, **accent lime `#C8FF2E`**
(text on accent: `#0A0B10`), danger `#FF4557`, warning/gold `#FFB021`,
purple `#7C5CFF` (text `#9F8BFF`), cyan `#22E5FF`, pink `#FF4D8D`, green `#39D98A`.
A light palette exists too; dark is the default and the brand.

Type: **Archivo** (body, weights 400–900), **Archivo Black italic** (display —
wordmark, "YOU WIN.", ghost VS), **Barlow Condensed 800 italic** (hero — scores,
section titles, ALL-CAPS pill buttons). Shapes: 999px pill buttons/chips,
8/12/16/20px card radii, 1px borders. Status→color: drafting = red (blinks),
pending/countered = purple, accepted/settled = lime, live dots blink.

UI kit primitives the screens compose (from `src/components/ui/`):

- **Avatar** — Initials tile with a stable per-name tint. Rounded square ("squircle"), per the Reimagined language. (8-digit hex appends alpha.)
- **Badge** — Small uppercase status pill. `tone` is one of the keys in theme `tones`. `dot` shows a leading dot; `blink` makes it pulse (live things blink).
- **BlinkDot** — The little live dot. blink=false renders it steady.
- **Button** — Condensed-italic pill buttons — the Reimagined CTA voice (ENTER ROOM →).
- **Card** — A surface with depth — border + soft shadow. Pass onPress to make it tappable.
- **Chip** — A selectable pill (filters, toggles). Light selection haptic on tap. Mirrors the Segmented recipe: center the label and let Barlow Condensed keep its NATURAL line height — forcing a lineHeight clips the glyphs on iOS.
- **EmptyState** — Friendly centered placeholder: an icon coin, a title, a subtitle, and an optional action node (e.g. a Button).
- **FadeIn** — Fade + slide a list row in on mount, lightly staggered by its index.
- **Field** — Labeled text input with optional password show/hide, a valid ✓, and an error.
- **GhostText** — Outline-only display text — the big translucent "VS" / pick-number watermarks. Rendered as stroked SVG text (RN has no text-stroke). Defaults to a faint stroke of the theme's text color, so it reads in light mode too.
- **Marquee** — Endless horizontal ticker: renders `children` twice and slides one copy's width, looping seamlessly. `speed` is px/second.
- **Pulse** — A soft expanding halo behind its children — the design's pulsing CTA ring.
- **Screen** — Page wrapper: themed bg, keyboard avoidance, and an optional scroll view with pull-to-refresh. No safe-area insets by default (the header owns the top, the tab bar owns the bottom).
- **SearchInput** — Text field with a leading search icon and a clear (×) button.
- **SectionHeader** — Condensed-italic section title, e.g. "YOUR MOVE", with an optional right hint ("3 PENDING"). Accepts a plain string child for back-compat.
- **Segmented** — The ACTIVE | PAST switch: a recessed track with a lime active segment. options: [{ key, label, count }]
- **Skeleton** — A single pulsing placeholder bar.
- **StatTile** — One tile of the 4-up stat grid: big condensed-italic value over a tiny kicker.
- **Type** — The three voices of the Reimagined type system. Tiny 800-weight uppercase tracking label: "SEASON RECORD", "PICK 3 OF 10".

## The screen source (`src/screens/SettingsScreen.js`)

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
});import { Alert, Platform, Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Constants from 'expo-constants';
import { useAuth } from '../auth/AuthContext';
import { usePrefs } from '../prefs';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, SectionHeader, Button } from '../components/ui';

const APPEARANCE = [
  { key: 'system', label: 'System', icon: 'phone-portrait-outline' },
  { key: 'light', label: 'Light', icon: 'sunny-outline' },
  { key: 'dark', label: 'Dark', icon: 'moon-outline' },
];

export default function SettingsScreen({ navigation }) {
  const { colors, mode, setMode } = useTheme();
  const { haptics, setHaptics } = usePrefs();
  const { signOut, deleteAccount } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const version = Constants.expoConfig?.version || '1.0.0';

  function confirmDelete() {
    Alert.alert(
      'Delete your account?',
      'This is permanent. Your profile is erased, live duels are cancelled and every stake is refunded. Finished duels stay in your friends’ history under an anonymous name.',
      [
        { text: 'Keep my account', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: askPassword },
      ]
    );
  }

  function askPassword() {
    if (Platform.OS !== 'ios') {
      Alert.alert('Not available', 'Account deletion is currently iOS-only — contact support.');
      return;
    }
    Alert.prompt(
      'Confirm with your password',
      'Enter your password to permanently delete this account.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete forever',
          style: 'destructive',
          onPress: (password) => {
            deleteAccount(password || '').catch((e) =>
              Alert.alert('Couldn’t delete', e?.message || 'Check your password and try again.')
            );
          },
        },
      ],
      'secure-text'
    );
  }

  return (
    <Screen scroll>
      <SectionHeader style={{ marginTop: 0 }}>Appearance</SectionHeader>
      <Card padded={false} style={{ padding: spacing.xs }}>
        <View style={styles.segment}>
          {APPEARANCE.map((opt) => {
            const active = mode === opt.key;
            return (
              <Pressable key={opt.key} onPress={() => setMode(opt.key)} style={[styles.segItem, active && styles.segItemActive]}>
                <Ionicons name={opt.icon} size={18} color={active ? colors.onAccent : colors.muted} />
                <Text style={[styles.segLabel, { color: active ? colors.onAccent : colors.muted }]}>{opt.label}</Text>
              </Pressable>
            );
          })}
        </View>
      </Card>

      <SectionHeader>Preferences</SectionHeader>
      <Card padded={false}>
        <View style={styles.row}>
          <View style={styles.rowIcon}>
            <Ionicons name="pulse" size={18} color={colors.accent} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.rowLabel}>Haptic feedback</Text>
            <Text style={styles.rowSub}>Vibrations on taps, picks and results</Text>
          </View>
          <Switch value={haptics} onValueChange={setHaptics} trackColor={{ true: colors.accent, false: colors.border }} thumbColor="#ffffff" />
        </View>
      </Card>

      <SectionHeader>Account</SectionHeader>
      <Card padded={false}>
        <Pressable onPress={() => navigation.navigate('ChangePassword')} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
          <View style={styles.rowIcon}>
            <Ionicons name="lock-closed-outline" size={18} color={colors.accent} />
          </View>
          <Text style={[styles.rowLabel, { flex: 1 }]}>Change password</Text>
          <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
        </Pressable>
        <Pressable onPress={() => navigation.navigate('Blocked')} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
          <View style={styles.rowIcon}>
            <Ionicons name="hand-left-outline" size={18} color={colors.accent} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.rowLabel}>Blocked players</Text>
            <Text style={styles.rowSub}>See who's blocked, undo it</Text>
          </View>
          <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
        </Pressable>
        <Pressable onPress={confirmDelete} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
          <View style={[styles.rowIcon, { backgroundColor: colors.dangerSoft }]}>
            <Ionicons name="trash-outline" size={18} color={colors.danger} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={[styles.rowLabel, { color: colors.danger }]}>Delete account</Text>
            <Text style={styles.rowSub}>Permanent — live duels cancel, stakes refund</Text>
          </View>
          <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
        </Pressable>
      </Card>

      <SectionHeader>About</SectionHeader>
      <Card>
        <View style={styles.aboutRow}>
          <Text style={styles.aboutLabel}>Version</Text>
          <Text style={styles.aboutValue}>{version}</Text>
        </View>
        <View style={[styles.aboutRow, { marginTop: spacing.sm }]}>
          <Text style={styles.aboutLabel}>App</Text>
          <Text style={styles.aboutValue}>Heads Up Fantasy</Text>
        </View>
      </Card>

      <View style={{ marginTop: spacing.xl }}>
        <Button title="Log Out" variant="danger" icon="log-out-outline" onPress={signOut} />
      </View>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    segment: { flexDirection: 'row', gap: spacing.xs },
    segItem: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 12, borderRadius: radius.md },
    segItemActive: { backgroundColor: colors.accent },
    segLabel: { fontSize: font.small, fontWeight: '700' },
    row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    rowIcon: {
      width: 34,
      height: 34,
      borderRadius: 10,
      backgroundColor: colors.accentSoft,
      alignItems: 'center',
      justifyContent: 'center',
      marginRight: spacing.md,
    },
    rowLabel: { color: colors.text, fontSize: font.bodyLg, fontWeight: '600' },
    rowSub: { color: colors.muted, fontSize: font.small, marginTop: 1 },
    aboutRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
    aboutLabel: { color: colors.muted, fontSize: font.body },
    aboutValue: { color: colors.text, fontSize: font.body, fontWeight: '600' },
  });
```
