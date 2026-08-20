# Rivalry page — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

One rivalry, whole (pushed from a FRIENDS row): face-off hero with the big series score and lead line, LAST 5 chips, three bragging-rights tiles (CURRENT RUN / AVG MARGIN / BEST WIN), the history as receipts with auto-generated story lines ("Collier 31.2 carried it"), and ⚔ CHALLENGE preseeding the composer. Friends you've never played get the honest 0–0 version.

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

## The screen source (`src/screens/RivalryScreen.js`)

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
});import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { blockUser, getRivalry } from '../api/social';
import { useTheme, useThemedStyles, avatarColor, spacing, fonts, withAlpha } from '../theme';
import { Screen, SkeletonList, EmptyState, Button } from '../components/ui';

// One rivalry, whole — from Saad's Reimagined drop: the face-off hero with the
// series score, LAST 5 chips, the bragging-rights tiles, and the history as
// receipts with story lines. Friends with no duels get the honest 0–0 version.
export default function RivalryScreen({ route, navigation }) {
  const { id, username } = route.params;
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [riv, setRiv] = useState(null);
  const [loading, setLoading] = useState(true);

  const [loadError, setLoadError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await getRivalry(token, id);
      setRiv(res.rivalry);
      setLoadError(null);
    } catch (e) {
      setLoadError(e.message || 'Could not load this rivalry.');
    } finally {
      setLoading(false);
    }
  }, [token, id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function challenge() {
    navigation.navigate('DuelsTab', { screen: 'CreateChallenge', params: { preselect: id }, initial: false });
  }

  function confirmBlock() {
    Alert.alert(
      `Block ${username}?`,
      'Shared live duels get cancelled and you disappear from each other. This also unfriends them.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Block',
          style: 'destructive',
          onPress: async () => {
            try {
              await blockUser(token, id);
              navigation.goBack();
            } catch (e) {
              Alert.alert("Couldn't block them", e.message);
            }
          },
        },
      ]
    );
  }

  if (loadError && !riv) {
    return (
      <Screen>
        <EmptyState
          icon="cloud-offline-outline"
          title="Couldn't load this rivalry"
          subtitle={loadError}
          action={<Button title="Try again" icon="refresh" onPress={() => { setLoading(true); load(); }} />}
        />
      </Screen>
    );
  }

  if (loading || !riv) {
    return (
      <Screen>
        <SkeletonList count={5} />
      </Screen>
    );
  }

  const theirTint = avatarColor(username);
  const played = riv.played > 0;
  const seriesLine = !played
    ? 'NO DUELS YET'
    : riv.wins > riv.losses
      ? 'YOU LEAD THE SERIES'
      : riv.wins < riv.losses
        ? 'THEY LEAD THE SERIES'
        : 'SERIES ALL SQUARE';

  const chip = (letter) =>
    letter === 'W'
      ? { bg: withAlpha(colors.accent, 0.16), bd: withAlpha(colors.accent, 0.55), ink: colors.accent }
      : letter === 'L'
        ? { bg: withAlpha(colors.danger, 0.14), bd: withAlpha(colors.danger, 0.55), ink: colors.danger }
        : { bg: withAlpha(colors.muted, 0.14), bd: withAlpha(colors.muted, 0.45), ink: colors.muted };

  const outcomePill = (o) =>
    o === 'win'
      ? { label: 'WIN', ...chip('W') }
      : o === 'loss'
        ? { label: 'LOSS', ...chip('L') }
        : { label: 'TIE', ...chip('T') };

  const signed = (n) => (n == null ? '—' : `${n >= 0 ? '+' : '−'}${Math.abs(n).toFixed(1)}`);

  const dateLabel = (iso) => {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' }).toUpperCase();
  };

  return (
    <Screen padded={false}>
      <ScrollView contentContainerStyle={{ paddingBottom: spacing.xxl }} showsVerticalScrollIndicator={false}>
        <LinearGradient
          colors={[withAlpha(colors.purpleText, 0.14), 'transparent']}
          start={{ x: 0.5, y: 0 }}
          end={{ x: 0.5, y: 1 }}
          style={{ paddingHorizontal: spacing.lg, paddingTop: spacing.xs }}
        >
          <View style={styles.heroCard}>
            <View style={styles.faceoff}>
              <View style={styles.corner}>
                <View style={[styles.bigAvatar, { backgroundColor: withAlpha(colors.accent, 0.16), borderColor: withAlpha(colors.accent, 0.5) }]}>
                  <Text style={[styles.bigAvatarText, { color: colors.accent }]}>
                    {(user?.username || '?')[0].toUpperCase()}
                  </Text>
                </View>
                <Text style={styles.cornerName} numberOfLines={1}>{user?.username}</Text>
              </View>
              <View style={styles.scoreCol}>
                <Text style={styles.bigScore} numberOfLines={1}>
                  <Text style={{ color: colors.accent }}>{riv.wins}</Text>
                  <Text style={{ color: colors.placeholder }}> – </Text>
                  <Text style={{ color: colors.text }}>{riv.losses}</Text>
                  {riv.ties > 0 ? <Text style={{ color: colors.placeholder, fontSize: 22 }}> –{riv.ties}</Text> : null}
                </Text>
                <Text style={styles.seriesLine}>{seriesLine}</Text>
              </View>
              <View style={styles.corner}>
                <View style={[styles.bigAvatar, { backgroundColor: theirTint + '26', borderColor: theirTint + '59' }]}>
                  <Text style={[styles.bigAvatarText, { color: theirTint }]}>{username[0].toUpperCase()}</Text>
                </View>
                <Text style={styles.cornerName} numberOfLines={1}>{username}</Text>
              </View>
            </View>

            {played && (
              <View style={styles.formRow}>
                <Text style={styles.formLabel}>LAST {riv.form.length}</Text>
                {riv.form.map((l, i) => {
                  const c = chip(l);
                  return (
                    <View key={i} style={[styles.formChip, { backgroundColor: c.bg, borderColor: c.bd }]}>
                      <Text style={[styles.formChipText, { color: c.ink }]}>{l}</Text>
                    </View>
                  );
                })}
              </View>
            )}
          </View>

          <View style={styles.tiles}>
            <View style={styles.tile}>
              <Text
                style={[
                  styles.tileValue,
                  {
                    color:
                      riv.run && riv.run.startsWith('W')
                        ? colors.accent
                        : riv.run && riv.run.startsWith('L')
                          ? colors.danger
                          : colors.text,
                  },
                ]}
              >
                {riv.run || '—'}
              </Text>
              <Text style={styles.tileKicker}>CURRENT RUN</Text>
            </View>
            <View style={styles.tile}>
              <Text style={styles.tileValue}>{signed(riv.avg_margin)}</Text>
              <Text style={styles.tileKicker}>AVG MARGIN</Text>
            </View>
            <View style={styles.tile}>
              <Text style={styles.tileValue}>{riv.best_win == null ? '—' : `+${riv.best_win.toFixed(1)}`}</Text>
              <Text style={styles.tileKicker}>BEST WIN</Text>
            </View>
          </View>
        </LinearGradient>

        <View style={styles.historyZone}>
          <Text style={styles.historyLabel}>HISTORY</Text>
          {played ? (
            <View style={styles.historyCard}>
              {riv.history.map((h, i) => {
                const pill = outcomePill(h.outcome);
                return (
                  <View key={i} style={[styles.histRow, i < riv.history.length - 1 && styles.histSep]}>
                    <View style={[styles.histPill, { backgroundColor: pill.bg, borderColor: pill.bd }]}>
                      <Text style={[styles.histPillText, { color: pill.ink }]}>{pill.label}</Text>
                    </View>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Text style={styles.histScore}>
                        {h.my_points.toFixed(1)} – {h.their_points.toFixed(1)}
                      </Text>
                      {h.story ? <Text style={styles.histStory} numberOfLines={1}>{h.story}</Text> : null}
                    </View>
                    <Text style={styles.histDate}>{dateLabel(h.settled_at)}</Text>
                  </View>
                );
              })}
            </View>
          ) : (
            <Text style={styles.historyEmpty}>The series starts when you send it.</Text>
          )}

          <Button
            title={`⚔ Challenge ${username}`}
            style={{ marginTop: spacing.lg }}
            onPress={challenge}
          />

          <Pressable onPress={confirmBlock} hitSlop={8} style={{ alignSelf: 'center', marginTop: spacing.lg }}>
            <Text style={{ color: colors.textFaint, fontSize: 11, fontFamily: fonts.bodyBold, letterSpacing: 0.5 }}>
              BLOCK {username.toUpperCase()}
            </Text>
          </Pressable>
        </View>
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    heroCard: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 16,
      paddingVertical: 20,
      paddingHorizontal: 14,
      alignItems: 'center',
    },
    faceoff: { flexDirection: 'row', alignItems: 'center', gap: 16 },
    corner: { alignItems: 'center', gap: 6, width: 76 },
    bigAvatar: {
      width: 52,
      height: 52,
      borderRadius: 26,
      borderWidth: 1,
      alignItems: 'center',
      justifyContent: 'center',
    },
    bigAvatarText: { fontFamily: fonts.bodyExtra, fontSize: 20 },
    cornerName: { fontSize: 11, fontFamily: fonts.bodyExtra, color: colors.muted, maxWidth: 76 },
    scoreCol: { alignItems: 'center', gap: 2, paddingHorizontal: 8 },
    bigScore: { fontFamily: fonts.hero, fontSize: 40, lineHeight: 42 },
    seriesLine: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 2, color: colors.placeholder },
    formRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 12 },
    formLabel: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.placeholder, marginRight: 3 },
    formChip: {
      width: 20,
      height: 20,
      borderRadius: 7,
      borderWidth: 1,
      alignItems: 'center',
      justifyContent: 'center',
    },
    formChipText: { fontSize: 9.5, fontFamily: fonts.bodyBlack },
    tiles: { flexDirection: 'row', gap: 8, marginTop: 10 },
    tile: {
      flex: 1,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
      paddingVertical: 11,
      alignItems: 'center',
    },
    tileValue: { fontFamily: fonts.hero, fontSize: 19, color: colors.text },
    tileKicker: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 1, color: colors.placeholder, marginTop: 2 },
    historyZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.lg },
    historyLabel: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.placeholder },
    historyCard: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 14,
      marginTop: 8,
      overflow: 'hidden',
    },
    histRow: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 14, paddingVertical: 11 },
    histSep: { borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
    histPill: { borderWidth: 1, borderRadius: 999, paddingHorizontal: 10, paddingVertical: 3, flexShrink: 0 },
    histPillText: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    histScore: { fontFamily: fonts.hero, fontSize: 16, color: colors.text },
    histStory: { fontSize: 10, color: colors.muted, marginTop: 1 },
    histDate: { fontSize: 9.5, fontFamily: fonts.bodyExtra, color: colors.placeholder, flexShrink: 0 },
    historyEmpty: { fontSize: 12, color: colors.placeholder, fontFamily: fonts.bodySemi, marginTop: 8 },
  });
```
