# Counter offer — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Re-terms a 1v1 challenge and sends it back (thin wrapper around the same ChallengeForm the builder uses).

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

## The screen source (`src/screens/CounterScreen.js`)

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
});import { useEffect, useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { counterChallenge } from '../api/duels';
import { getSportsStatus } from '../api/sports';
import ChallengeForm from '../components/ChallengeForm';
import { useThemedStyles, spacing, font } from '../theme';
import { Screen, Card } from '../components/ui';

export default function CounterScreen({ route, navigation }) {
  const { id, initial } = route.params;
  const { token, refreshUser } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);
  const [sportsStatus, setSportsStatus] = useState(null);

  // Same off-season gate the composer applies — countering into a dead league
  // used to be rejected only after submit.
  useEffect(() => {
    getSportsStatus(token)
      .then((r) => setSportsStatus(r.sports))
      .catch(() => {});
  }, [token]);

  async function submit(terms) {
    setSubmitting(true);
    setError(null);
    try {
      const res = await counterChallenge(token, id, terms);
      refreshUser(); // old stake refunded, new stake escrowed
      navigation.replace('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setError(e.message);
      setSubmitting(false);
    }
  }

  return (
    <Screen scroll>
      <Card style={{ marginBottom: spacing.md }}>
        <Text style={styles.intro}>
          Change the terms and send it back. They'll get a new challenge to accept, decline, or counter again.
        </Text>
      </Card>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <ChallengeForm
        initial={initial}
        onSubmit={submit}
        submitLabel="Send Counter"
        submitting={submitting}
        sportsStatus={sportsStatus}
      />
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, lineHeight: 21 },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.md },
  });
```

## Shared component it uses: `ChallengeForm.js`

```jsx
import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { listSlates } from '../api/sports';
import { useThemedStyles, spacing, font, fonts } from '../theme';
import { Chip, Button } from './ui';

// WNBA, MLB and NFL are live (real ESPN rosters/stats); NBA still uses a
// placeholder pool until its season + feed are wired, so the live ones lead.
// Off-season sports are dimmed by isPlayable below, not removed.
const SPORTS = [
  { key: 'wnba', label: '🏀 WNBA' },
  { key: 'mlb', label: '⚾️ Baseball' },
  { key: 'nfl', label: '🏈 Football' },
  { key: 'nba', label: '🏀 Basketball' },
];

// Off-season sports can't be picked (no games in the window = nothing to
// score). Unknown status (endpoint unreachable) fails open — the server
// backstops creation anyway.
function isPlayable(sportsStatus, key) {
  const st = sportsStatus?.find?.((s) => s.sport === key);
  return !st || st.playable;
}

// Roster sizes and clocks match the canonical challenge screen (async cut).
// Baseball runs 6/9; everyone else 5/7 — mirrors Drafts.Lineup.sizes_for/1.
const ROSTERS_BY_LEAGUE = { mlb: [6, 9] };
const rosterSizesFor = (lg) => ROSTERS_BY_LEAGUE[lg] || [5, 7];

const CLOCKS = [
  { secs: 15, label: '15s' },
  { secs: 30, label: '30s' },
  { secs: 60, label: '60s' },
];

const TIME_OPTIONS = [
  { label: 'In 1 hour', ms: 60 * 60 * 1000 },
  { label: 'In 3 hours', ms: 3 * 60 * 60 * 1000 },
  { label: 'Tomorrow', ms: 24 * 60 * 60 * 1000 },
  { label: 'In 2 days', ms: 2 * 24 * 60 * 60 * 1000 },
];

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

import { etDayISO } from '../time';

// "Tonight" / "Tomorrow" / "Wed Jul 15" for a slate's ISO date.
function slateLabel(iso) {
  const today = etDayISO(Date.now());
  const tomorrow = etDayISO(Date.now() + 24 * 3600 * 1000);
  if (iso === today) return 'Tonight';
  if (iso === tomorrow) return 'Tomorrow';
  const d = new Date(`${iso}T12:00:00Z`);
  return `${WEEKDAYS[d.getUTCDay()]} ${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

// Coin stakes: every player antes the same amount into escrow; winner takes
// the pot. 0 = friendly (bragging rights only).
const STAKES = [
  { coins: 0, label: 'Friendly' },
  { coins: 25, label: '◎ 25' },
  { coins: 100, label: '◎ 100' },
  { coins: 500, label: '◎ 500' },
];

export default function ChallengeForm({ initial = {}, onSubmit, submitLabel, submitting, sportsStatus }) {
  const styles = useThemedStyles(makeStyles);
  const { user, token } = useAuth();
  const [sport, setSport] = useState(initial.sport || 'wnba');
  const [roster, setRoster] = useState(() => {
    const sizes = rosterSizesFor(initial.sport || 'wnba');
    const n = parseInt((initial.lineup_template || '').split('_')[1], 10);
    return sizes.includes(n) ? n : sizes[0];
  });
  // A countered async duel falls back to the shortest clock we still offer.
  const [clockSecs, setClockSecs] = useState(() =>
    CLOCKS.some((c) => c.secs === initial.pick_clock_seconds) ? initial.pick_clock_seconds : 30
  );
  const [timeMs, setTimeMs] = useState(TIME_OPTIONS[0].ms);
  const [stake, setStake] = useState(initial.stake_coins || 0);
  // Slates come in two shapes. Basketball and baseball answer with ET DAYS;
  // football answers with WEEKS, because a team there plays once and a single
  // night would offer two teams instead of the league. `slateId` is whichever
  // identifies the pick — an ISO date, or a week key like "1-2".
  const [slates, setSlates] = useState([]);
  const [slateKind, setSlateKind] = useState('day');
  const [slateId, setSlateId] = useState(null);

  const balance = user?.coins ?? 0;

  // Each sport has its own size menu — switching sports snaps to it.
  useEffect(() => {
    const sizes = rosterSizesFor(sport);
    if (!sizes.includes(roster)) setRoster(sizes[0]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sport]);

  // If the selected sport turns out to be off-season, snap to the first
  // playable one once status arrives.
  useEffect(() => {
    if (sportsStatus && !isPlayable(sportsStatus, sport)) {
      const first = SPORTS.find((s) => isPlayable(sportsStatus, s.key));
      if (first) setSport(first.key);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sportsStatus]);

  // A day is pickable if games there haven't all tipped yet (the server
  // rejects tipped-out days — you'd be drafting known stat lines).
  const pickable = (d) => (d.upcoming ?? d.games) > 0;

  // The sport's next week of slates; default = the countered duel's slate
  // when it's still live, else the first day with playable games. An empty
  // answer (feed down) hides the picker — the server defaults.
  useEffect(() => {
    let live = true;
    setSlates([]);
    setSlateId(null);
    listSlates(token, sport)
      .then((res) => {
        if (!live) return;
        const kind = res.kind || 'day';
        const list = res.slates || [];
        setSlateKind(kind);
        setSlates(list);
        const idOf = (s) => (kind === 'week' ? s.key : s.date);
        const fromInitial =
          initial.slate_date && sport === initial.sport
            ? list.find((s) => s.date === initial.slate_date && pickable(s))
            : null;
        const first = fromInitial || list.find(pickable);
        if (first) setSlateId(idOf(first));
      })
      .catch(() => {});
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, sport]);

  const idOf = (s) => (slateKind === 'week' ? s.key : s.date);
  const selectedSlate = slates.find((s) => idOf(s) === slateId) || null;
  // A week's first game is what the draft has to beat, not its last.
  const slateStart = selectedSlate?.date || null;

  const anyGated = SPORTS.some((s) => !isPlayable(sportsStatus, s.key));

  // The draft has to happen on or before the slate day — dim times past it,
  // and snap back to the first legal one if the pick went stale. If NO time
  // fits (late night: every option crosses into the next ET day), bump the
  // slate forward instead of dead-ending the form.
  const timeAllowed = (ms) => !slateStart || etDayISO(Date.now() + ms) <= slateStart;

  useEffect(() => {
    if (timeAllowed(timeMs)) return;
    const first = TIME_OPTIONS.find((t) => timeAllowed(t.ms));
    if (first) {
      setTimeMs(first.ms);
    } else {
      const next = slates.find((s) => pickable(s) && s.date > slateStart);
      if (next) setSlateId(idOf(next));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slateStart, slates]);

  function handleSubmit() {
    onSubmit({
      sport,
      lineup_template: `${sport}_${roster}`,
      pick_clock_seconds: clockSecs,
      draft_starts_at: new Date(Date.now() + timeMs).toISOString(),
      stake_coins: stake,
      ...(slateId ? (slateKind === 'week' ? { slate_week: slateId } : { slate_date: slateId }) : {}),
    });
  }

  return (
    <View>
      <Text style={styles.label}>Sport</Text>
      <View style={styles.row}>
        {SPORTS.map((s) => {
          const ok = isPlayable(sportsStatus, s.key);
          return (
            <View key={s.key} style={!ok && { opacity: 0.4 }}>
              <Chip label={ok ? s.label : `${s.label} · off-season`} active={sport === s.key} onPress={() => ok && setSport(s.key)} />
            </View>
          );
        })}
      </View>
      {anyGated ? <Text style={styles.gateNote}>Off-season sports come back when real games are on the slate.</Text> : null}

      {slates.some(pickable) ? (
        <>
          <Text style={styles.label}>{slateKind === 'week' ? 'Week — whose games count' : 'Slate — whose games count'}</Text>
          <View style={styles.row}>
            {slates
              .filter((s) => pickable(s) || idOf(s) === slateId)
              .slice(0, 5)
              .map((s) => (
                <Chip
                  key={idOf(s)}
                  label={`${slateKind === 'week' ? s.label : slateLabel(s.date)} · ${s.upcoming ?? s.games}`}
                  active={slateId === idOf(s)}
                  onPress={() => setSlateId(idOf(s))}
                />
              ))}
          </View>
          <Text style={styles.gateNote}>
            {slateKind === 'week'
              ? `Football runs by the week — every team plays once. You'll draft from all of ${
                  selectedSlate?.label?.toLowerCase() || 'that week'
                }, and it settles after the last game.`
              : `You'll only draft players who play ${
                  slateStart ? slateLabel(slateStart).toLowerCase() : 'that day'
                } — scoring covers just that slate.`}
          </Text>
        </>
      ) : null}

      <Text style={styles.label}>Roster</Text>
      <View style={styles.row}>
        {rosterSizesFor(sport).map((n) => (
          <Chip key={n} label={`${n} slots`} active={roster === n} onPress={() => setRoster(n)} />
        ))}
      </View>

      <Text style={styles.label}>Pick clock</Text>
      <View style={styles.row}>
        {CLOCKS.map((c) => (
          <Chip key={c.secs} label={c.label} active={clockSecs === c.secs} onPress={() => setClockSecs(c.secs)} />
        ))}
      </View>

      <Text style={styles.label}>When's the draft?</Text>
      <View style={styles.row}>
        {TIME_OPTIONS.map((t) => {
          const ok = timeAllowed(t.ms);
          return (
            <View key={t.label} style={!ok && { opacity: 0.4 }}>
              <Chip label={t.label} active={timeMs === t.ms} onPress={() => ok && setTimeMs(t.ms)} />
            </View>
          );
        })}
      </View>

      <Text style={styles.label}>Stake</Text>
      <View style={styles.row}>
        {STAKES.map((s) => {
          const affordable = s.coins <= balance;
          return (
            <View key={s.coins} style={!affordable && { opacity: 0.4 }}>
              <Chip label={s.label} active={stake === s.coins} onPress={() => affordable && setStake(s.coins)} />
            </View>
          );
        })}
      </View>
      <Text style={styles.stakeNote}>
        {stake === 0
          ? `Bragging rights only. You have ◎ ${balance.toLocaleString()}.`
          : `Everyone puts in ◎ ${stake} — winner takes all. You have ◎ ${balance.toLocaleString()}.`}
      </Text>

      <Text style={styles.note}>Standard {sport.toUpperCase()} scoring applies — the full chart is shown on the challenge.</Text>

      <Button title={submitLabel} icon="send" onPress={handleSubmit} loading={submitting} style={{ marginTop: spacing.xl }} />
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    label: {
      color: colors.placeholder,
      fontSize: 10,
      fontFamily: fonts.bodyExtra,
      letterSpacing: 2,
      textTransform: 'uppercase',
      marginTop: spacing.lg,
      marginBottom: spacing.sm,
    },
    row: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
    note: { color: colors.muted, fontSize: font.small, marginTop: spacing.lg, lineHeight: 19 },
    gateNote: { color: colors.placeholder, fontSize: font.caption, marginTop: spacing.sm },
    stakeNote: { color: colors.gold, fontSize: font.caption, marginTop: spacing.sm },
  });
```
