# Live hub (LIVE tab) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Your in-play matchups up top (score vs score, ticking), the real-games scoreboard folded in underneath (league chips, day strip, game rows). Empty top half: NOTHING ON THE LINE TONIGHT.

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

## The screen source (`src/screens/LiveHubScreen.js`)

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
import { ScrollView, StyleSheet, Text, View, Pressable } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { listDuels, getLiveResult } from '../api/duels';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Badge, Button, Kicker, CondTitle, GhostText, SkeletonList } from '../components/ui';

const ordinalShort = (n) => (n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`);

// One in-play duel as a scoreboard card: totals, momentum bar, games line.
// Polls /live every 20s while the tab is focused; goes quiet once settled.
function LiveDuelCard({ token, duel, onOpen, colors, styles }) {
  const [live, setLive] = useState(null);
  const [settled, setSettled] = useState(false);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
        try {
          const res = await getLiveResult(token, duel.id);
          if (active) setLive(res);
        } catch (e) {
          // Only a 409 means the duel settled; a network blip must not
          // freeze the card on "Final" while scores keep moving.
          if (active && e.status === 409) setSettled(true);
        }
      };
      tick();
      const iv = setInterval(tick, 20000);
      return () => {
        active = false;
        clearInterval(iv);
      };
    }, [token, duel.id])
  );

  const oppName = duel.opponent?.username || 'THEM';
  let me = 0;
  let them = 0;
  let themLabel = oppName;
  let rankLine = null;

  if (live?.challenger) {
    const mine = live.challenger.is_me ? live.challenger : live.opponent;
    const theirs = live.challenger.is_me ? live.opponent : live.challenger;
    me = mine?.total ?? 0;
    them = theirs?.total ?? 0;
    themLabel = theirs?.username || oppName;
  } else if (live?.sides) {
    const idx = live.sides.findIndex((s) => s.is_me);
    const mine = live.sides[idx];
    const best = live.sides.find((s) => !s.is_me);
    me = mine?.total ?? 0;
    them = best?.total ?? 0;
    themLabel = best?.user?.username || 'FIELD';
    if (mine) rankLine = `${ordinalShort(idx + 1)} OF ${live.sides.length}`;
  }

  const gamesLive = (live?.games?.live || 0) > 0;
  const total = me + them;
  const pct = total <= 0 ? 50 : Math.max(8, Math.min(92, (me / total) * 100));
  const diff = me - them;
  const leadText =
    live == null
      ? 'SYNCING THE BOX SCORES…'
      : diff === 0
        ? 'DEAD EVEN'
        : diff > 0
          ? `YOU LEAD BY ${diff.toFixed(1)}`
          : `DOWN ${Math.abs(diff).toFixed(1)} — RALLY TIME`;
  const gamesLine = live?.games
    ? `${live.games.final || 0} FINAL · ${live.games.live || 0} LIVE · ${live.games.upcoming || 0} TO TIP`
    : '';

  return (
    <Pressable onPress={onOpen} style={({ pressed }) => [styles.scoreCard, pressed && { transform: [{ scale: 0.98 }] }]}>
      <View style={styles.scoreTop}>
        <Kicker size={9}>{`HEAD-TO-HEAD · ${(duel.sport || '').toUpperCase()}`}</Kicker>
        {settled ? (
          <Badge label="Final" tone="neutral" />
        ) : gamesLive ? (
          <Badge label="Live" tone="danger" blink />
        ) : (
          <Badge label="In play" tone="info" />
        )}
      </View>

      <View style={styles.scoreRow}>
        <View>
          <Kicker size={10} color={colors.accent} tracking={1}>
            You
          </Kicker>
          <CondTitle size={40} color={me >= them ? colors.accent : colors.text}>
            {me.toFixed(1)}
          </CondTitle>
        </View>
        <GhostText size={17} color={withAlpha(colors.textFaint, 0.9)} strokeWidth={1}>
          VS
        </GhostText>
        <View style={{ alignItems: 'flex-end' }}>
          <Kicker size={10} color={colors.purpleText} tracking={1}>
            {themLabel}
          </Kicker>
          <CondTitle size={40} color={them > me ? colors.purpleText : colors.text}>
            {them.toFixed(1)}
          </CondTitle>
        </View>
      </View>

      <View style={styles.momTrack}>
        <View style={[styles.momFill, { width: `${pct}%` }]} />
      </View>
      <View style={styles.scoreFoot}>
        <Text style={styles.leadText}>{rankLine ? `${rankLine} · ${leadText}` : leadText}</Text>
        <Text style={styles.gamesLine}>{gamesLine}</Text>
      </View>
    </Pressable>
  );
}

export default function LiveHubScreen({ navigation }) {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duels, setDuels] = useState(null);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listDuels(token);
      setDuels(res.duels || []);
      setError(null);
    } catch (e) {
      setError(e.message);
      if (duels == null) setDuels([]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const inPlay = (duels || []).filter((d) => d.status === 'drafted');

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView contentContainerStyle={styles.body} showsVerticalScrollIndicator={false}>
        <Kicker tracking={3} style={{ textAlign: 'center', marginTop: spacing.sm }}>
          Live
        </Kicker>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {duels == null ? (
          <View style={{ marginTop: spacing.xl }}>
            <SkeletonList count={3} />
          </View>
        ) : inPlay.length === 0 ? (
          <View style={styles.emptyWrap}>
            <View style={styles.lockCoin}>
              <Ionicons name="lock-closed" size={26} color={colors.placeholder} />
            </View>
            <CondTitle size={20} color={colors.muted} style={{ textAlign: 'center', letterSpacing: 1 }}>
              FINISH YOUR DRAFT TO GO LIVE
            </CondTitle>
            <Text style={styles.emptySub}>
              Once both slips are sealed, tonight's real box scores play out right here.
            </Text>
            <Button
              title="To the draft room"
              full={false}
              style={{ marginTop: spacing.lg, alignSelf: 'center' }}
              onPress={() => navigation.navigate('DraftTab')}
            />
          </View>
        ) : (
          <View style={{ gap: spacing.md, marginTop: spacing.lg }}>
            {inPlay.map((d) => (
              <LiveDuelCard
                key={d.id}
                token={token}
                duel={d}
                colors={colors}
                styles={styles}
                onOpen={() =>
                  navigation.navigate('DuelsTab', {
                    screen: 'LiveMatchup',
                    params: { id: d.id, opponentName: d.opponent?.username },
                    initial: false,
                  })
                }
              />
            ))}
          </View>
        )}

        <View style={styles.slateRow}>
          <View style={{ flex: 1 }}>
            <CondTitle size={17} style={{ letterSpacing: 1 }}>
              TONIGHT'S SLATE
            </CondTitle>
            <Text style={styles.slateSub}>Real games, live box scores, player form.</Text>
          </View>
          <Button title="Scoreboard →" size="sm" full={false} variant="outline" onPress={() => navigation.navigate('Games')} />
        </View>
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { padding: spacing.lg, paddingBottom: spacing.xxl },
    scoreCard: {
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
      padding: spacing.lg,
      overflow: 'hidden',
    },
    scoreTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    scoreRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.sm },
    momTrack: {
      height: 7,
      borderRadius: 4,
      backgroundColor: withAlpha(colors.purple, 0.35),
      overflow: 'hidden',
      marginTop: spacing.sm,
    },
    momFill: { height: '100%', borderRadius: 4, backgroundColor: colors.accent },
    scoreFoot: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 6 },
    leadText: { fontSize: 9.5, fontFamily: fonts.bodyExtra, color: colors.muted, letterSpacing: 0.3 },
    gamesLine: { fontSize: 9.5, fontFamily: fonts.bodyBold, color: colors.placeholder },
    emptyWrap: { alignItems: 'center', paddingTop: 110, paddingHorizontal: spacing.xl },
    lockCoin: {
      width: 64,
      height: 64,
      borderRadius: 20,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: spacing.lg,
    },
    emptySub: { color: colors.muted, fontSize: 13, textAlign: 'center', marginTop: spacing.sm, lineHeight: 19, fontFamily: fonts.body },
    slateRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
      marginTop: spacing.xl,
      borderTopWidth: 1,
      borderTopColor: colors.borderSubtle,
      paddingTop: spacing.lg,
    },
    slateSub: { color: colors.muted, fontSize: 12, marginTop: 3, fontFamily: fonts.body },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
```
