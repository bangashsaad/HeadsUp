# New challenge — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

The challenge builder (pushed from DUELS or the + CTA). Pick rivals (up to 3 — group duels), league (off-season ones dimmed OFF-SEASON), slate (day for WNBA/MLB/NBA, week for NFL), roster (🏀🏈 5/7 · ⚾️ 6/9), stake none/◎25/◎100, clock 15/30/60s, then THE TERMS receipt rail and SEND IT. Scoring chart viewable per league.

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

## The screen source (`src/screens/CreateChallengeScreen.js`)

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
});import { useCallback, useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listFriends, listFriendGroups } from '../api/social';
import { getSportsStatus, listSlates } from '../api/sports';
import { createChallenge } from '../api/duels';
import { selection, impact, ImpactStyle } from '../haptics';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList, Button } from '../components/ui';

// Host + 4 rivals. Mirrors Participant.max_seat on the server.
const MAX_RIVALS = 4;

const LEAGUES = [
  { key: 'wnba', label: 'WNBA' },
  { key: 'mlb', label: 'MLB' },
  { key: 'nba', label: 'NBA' },
  { key: 'nfl', label: 'NFL' },
];

// Per-sport roster menus. Baseball runs 6 (one ace + five bats) and 9 (the
// whole diamond); everyone else 5/7. Mirrors Drafts.Lineup.sizes_for/1.
const ROSTERS_BY_LEAGUE = { mlb: [6, 9] };
const rosterSizesFor = (lg) => ROSTERS_BY_LEAGUE[lg] || [5, 7];
const CLOCKS = [15, 30, 60];
const STAKES = [
  { coins: 0, label: 'FRIENDLY' },
  { coins: 25, label: '25' },
  { coins: 100, label: '100' },
];

// Display copy for the Roster Shapes modal. Mirrors Drafts.Lineup — the server
// is the authority; this only explains the shape you're picking.
const SHAPES = {
  wnba: { 5: ['2 GUARD', '2 FORWARD', '1 FLEX'], 7: ['3 GUARD', '3 FORWARD', '1 FLEX'] },
  nba: { 5: ['2 GUARD', '2 FORWARD', '1 FLEX'], 7: ['3 GUARD', '3 FORWARD', '1 FLEX'] },
  mlb: {
    6: ['1 PITCHER', '2 INFIELD', '2 OUTFIELD', '1 UTIL'],
    9: ['1 PITCHER', 'C · 1B · 2B · 3B · SS', '3 OUTFIELD'],
  },
  nfl: {
    5: ['1 QB', '1 RB', '2 WR', '1 FLEX'],
    7: ['1 QB', '2 RB', '2 WR', '1 TE', '1 FLEX'],
  },
};

const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

import { etDayISO } from '../time';

function slateLabel(iso) {
  if (iso === etDayISO(Date.now())) return 'TONIGHT';
  if (iso === etDayISO(Date.now() + 86400000)) return 'TOMORROW';
  const d = new Date(`${iso}T12:00:00Z`);
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

const isPlayable = (status, key) => {
  const st = status?.find?.((s) => s.sport === key);
  return !st || st.playable;
};

export default function CreateChallengeScreen({ navigation, route }) {
  // Tapping a face on Home's friend strip lands here with them already picked.
  const preselect = route?.params?.preselect;
  const { token, user, refreshUser } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [friends, setFriends] = useState([]);
  const [groups, setGroups] = useState([]);
  const [sportsStatus, setSportsStatus] = useState(null);
  const [slates, setSlates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  // Step 1 — the duel
  const [league, setLeague] = useState('wnba');
  // Basketball and baseball pick an ET DAY; football picks a WEEK, since a
  // team there plays once and a single night is two teams, not a league.
  // `slateId` holds whichever identifies the pick — an ISO date or "1-2".
  const [slateKind, setSlateKind] = useState('day');
  const [slateId, setSlateId] = useState(null);
  const [roster, setRoster] = useState(5);
  const [stake, setStake] = useState(0);
  const [customStake, setCustomStake] = useState('');
  const [customOpen, setCustomOpen] = useState(false);
  const [clock, setClock] = useState(30);
  const [shapesOpen, setShapesOpen] = useState(false);

  // Step 2 — send it to
  const [tab, setTab] = useState('everyone');
  const [selected, setSelected] = useState([]);
  const [reloadKey, setReloadKey] = useState(0);

  const balance = user?.coins ?? 0;

  useEffect(() => {
    (async () => {
      try {
        const [f, g] = await Promise.all([listFriends(token), listFriendGroups(token).catch(() => ({ groups: [] }))]);
        const list = f.friends || [];
        setFriends(list);
        setGroups(g.groups || []);
        // Only honour it if they're really a friend — a stale param shouldn't
        // put a phantom id into the selection.
        if (preselect && list.some((x) => x.id === preselect)) setSelected([preselect]);
      } catch (e) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    })();
    getSportsStatus(token)
      .then((r) => setSportsStatus(r.sports))
      .catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, reloadKey]);

  // Re-pull friends/groups on focus so a group made on the Friends tab shows up.
  useFocusEffect(
    useCallback(() => {
      listFriendGroups(token)
        .then((g) => setGroups(g.groups || []))
        .catch(() => {});
    }, [token])
  );

  // Slates for the chosen league; default to the first day with untipped games.
  useEffect(() => {
    let live = true;
    setSlates([]);
    setSlateId(null);
    listSlates(token, league)
      .then((res) => {
        if (!live) return;
        const kind = res.kind || 'day';
        const list = res.slates || [];
        setSlateKind(kind);
        setSlates(list);
        const first = list.find((d) => (d.upcoming ?? d.games) > 0);
        if (first) setSlateId(kind === 'week' ? first.key : first.date);
      })
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [token, league]);

  // Snap off an off-season league once the gate answers.
  useEffect(() => {
    if (sportsStatus && !isPlayable(sportsStatus, league)) {
      const first = LEAGUES.find((l) => isPlayable(sportsStatus, l.key));
      if (first) setLeague(first.key);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sportsStatus]);

  const playableLeagues = LEAGUES.filter((l) => isPlayable(sportsStatus, l.key));
  const slateIdOf = (d) => (slateKind === 'week' ? d.key : d.date);
  const slate = slates.find((d) => slateIdOf(d) === slateId);
  const slatePlayers = slate?.players ?? null;
  // The label a human reads, and the first day the draft has to beat.
  const slateName = slateKind === 'week' ? slate?.label || 'that week' : slateLabel(slate?.date || '');
  const slateStart = slate?.date || null;

  // The server rejects a slate that can't field roster x drafters x 2 bodies.
  // Mirror that here so sizes (and extra rivals) grey out BEFORE you send.
  const fits = useCallback(
    (size, drafters) => slatePlayers == null || slatePlayers >= size * drafters * 2,
    [slatePlayers]
  );

  const drafters = selected.length + 1;
  const rosterSizes = rosterSizesFor(league);
  const rosterOk = (size) => fits(size, Math.max(drafters, 2));
  const canAddAnother = fits(roster, Math.max(drafters + 1, 2));

  // Each sport has its own size menu — switching leagues snaps to it.
  useEffect(() => {
    if (!rosterSizes.includes(roster)) setRoster(rosterSizes[0]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [league]);

  // If the picked roster stops fitting (slate changed, or a rival joined),
  // fall back to the largest size that still works.
  useEffect(() => {
    if (!rosterOk(roster)) {
      const ok = [...rosterSizes].reverse().find((s) => rosterOk(s));
      if (ok) setRoster(ok);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slateId, slatePlayers, selected.length]);

  const visibleFriends = useMemo(() => {
    const base = [...friends].sort((a, b) => a.username.localeCompare(b.username));
    if (tab === 'everyone') return base;
    const g = groups.find((x) => String(x.id) === String(tab));
    if (!g) return base;
    const ids = new Set(g.member_ids || []);
    return base.filter((f) => ids.has(f.id));
  }, [friends, groups, tab]);

  function toggle(id) {
    setError(null);
    setSelected((cur) => {
      if (cur.includes(id)) {
        selection();
        return cur.filter((x) => x !== id);
      }
      if (cur.length >= MAX_RIVALS) {
        setError(`${MAX_RIVALS} rivals max — ${MAX_RIVALS + 1} drafters per duel.`);
        return cur;
      }
      if (!canAddAnother) {
        setError(`This slate can't field a ${roster}-slot draft for ${cur.length + 2} players.`);
        return cur;
      }
      impact(ImpactStyle.Light);
      return [...cur, id];
    });
  }

  const effectiveStake = stake === -1 ? Math.max(0, parseInt(customStake, 10) || 0) : stake;
  const stakeLabel =
    stake === -1 ? `◎ ${effectiveStake.toLocaleString()}` : stake === 0 ? 'FRIENDLY' : `◎ ${stake}`;
  const stakeAffordable = effectiveStake <= balance;

  // Leaving the custom sheet without a usable amount reverts to Friendly, so
  // the footer can never advertise "◎ 0" as a custom stake.
  function closeCustom() {
    setCustomOpen(false);
    const n = parseInt(customStake, 10) || 0;
    if (n < 1 || n > balance) {
      setStake(0);
      setCustomStake('');
    }
  }

  // BUG GUARD: a thin slate can leave NO roster size viable for the current
  // table (pick 4 rivals on a big slate, then switch to a one-game night).
  // Without this the CTA stayed live and the server rejected the send.
  const anyRosterFits = rosterSizes.some((size) => rosterOk(size));

  async function send() {
    if (selected.length === 0) return;
    if (!stakeAffordable) {
      setError(`You only have ◎ ${balance.toLocaleString()}.`);
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const who = selected.length === 1 ? { opponent_id: selected[0] } : { opponent_ids: selected };
      const res = await createChallenge(token, {
        ...who,
        sport: league,
        lineup_template: `${league}_${roster}`,
        pick_clock_seconds: clock,
        stake_coins: effectiveStake,
        draft_starts_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
        ...(slateId ? (slateKind === 'week' ? { slate_week: slateId } : { slate_date: slateId }) : {}),
      });
      refreshUser();
      // Straight to the lobby: watch acceptances land, then start.
      navigation.replace('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return (
      <Screen>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  if (friends.length === 0) {
    return (
      <Screen>
        {error ? (
          <EmptyState
            icon="cloud-offline-outline"
            title="Couldn't load your crew"
            subtitle={error}
            action={
              <Button
                title="Try again"
                icon="refresh"
                onPress={() => {
                  setError(null);
                  setLoading(true);
                  setReloadKey((k) => k + 1);
                }}
              />
            }
          />
        ) : (
          <EmptyState
            icon="people-outline"
            title="A duel needs a rival"
            subtitle="Add a friend from the Friends tab first — then come back and set the terms."
          />
        )}
      </Screen>
    );
  }

  const cta = !anyRosterFits
    ? 'SLATE TOO SMALL'
    : selected.length === 0
      ? 'PICK WHO GETS IT'
      : selected.length === 1
        ? 'SEND TO 1'
        : `SEND TO ${selected.length}`;

  return (
    <Screen padded={false} edges={['bottom']}>
      <ScrollView contentContainerStyle={{ padding: spacing.lg, paddingBottom: 132 }} showsVerticalScrollIndicator={false}>
        <StepLabel n="1" title="THE DUEL" styles={styles} />

        <View style={styles.card}>
          <Row label="LEAGUE" styles={styles}>
            {playableLeagues.map((l) => (
              <Opt key={l.key} label={l.label} active={league === l.key} onPress={() => setLeague(l.key)} styles={styles} />
            ))}
          </Row>

          {slates.some((d) => (d.upcoming ?? d.games) > 0) ? (
            <Row label="SLATE" styles={styles} scroll>
              {slates
                .filter((d) => (d.upcoming ?? d.games) > 0 || slateIdOf(d) === slateId)
                .slice(0, 5)
                .map((d) => (
                  <Opt
                    key={slateIdOf(d)}
                    label={`${slateKind === 'week' ? d.label : slateLabel(d.date)} · ${d.upcoming ?? d.games}`}
                    active={slateId === slateIdOf(d)}
                    onPress={() => setSlateId(slateIdOf(d))}
                    styles={styles}
                  />
                ))}
            </Row>
          ) : null}

          <Row
            label="ROSTER"
            styles={styles}
            info={() => {
              selection();
              setShapesOpen(true);
            }}
          >
            {rosterSizes.map((size) => {
              const ok = rosterOk(size);
              return (
                <Opt
                  key={size}
                  label={String(size)}
                  active={roster === size}
                  disabled={!ok}
                  onPress={() => ok && setRoster(size)}
                  styles={styles}
                />
              );
            })}
          </Row>

          <Row label="STAKE" styles={styles}>
            {STAKES.map((s) => (
              <Opt
                key={s.coins}
                label={s.label}
                active={stake === s.coins}
                disabled={s.coins > balance}
                onPress={() => s.coins <= balance && setStake(s.coins)}
                styles={styles}
              />
            ))}
            <Opt
              label={stake === -1 && effectiveStake > 0 ? `◎ ${effectiveStake}` : 'CUSTOM'}
              active={stake === -1}
              onPress={() => {
                setStake(-1);
                setCustomOpen(true);
              }}
              styles={styles}
            />
          </Row>

          <Row label="PICK CLOCK" styles={styles} last>
            {CLOCKS.map((c) => (
              <Opt key={c} label={`${c}s`} active={clock === c} onPress={() => setClock(c)} styles={styles} />
            ))}
          </Row>
        </View>

        {slatePlayers != null && !anyRosterFits ? (
          <Text style={[styles.note, { color: colors.danger }]}>
            {slateName} can't field a draft for {drafters} players. Pick a bigger slate, or drop a
            rival.
          </Text>
        ) : slatePlayers != null && !rosterOk(7) ? (
          <Text style={styles.note}>
            {slateName} has {slate?.upcoming ?? 0} game{(slate?.upcoming ?? 0) === 1 ? '' : 's'} — not
            enough players for every roster size. Pick a bigger slate for deeper drafts.
          </Text>
        ) : null}

        <View style={styles.stepRow}>
          <StepLabel n="2" title="SEND IT TO" styles={styles} />
          <Text style={styles.counter}>
            {selected.length} / {MAX_RIVALS} SELECTED
          </Text>
        </View>

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, flexShrink: 0 }}>
          <View style={styles.tabRow}>
            <Tab label={`EVERYONE ${friends.length}`} active={tab === 'everyone'} onPress={() => setTab('everyone')} styles={styles} />
            {groups.map((g) => (
              <Tab
                key={g.id}
                label={`${g.name.toUpperCase()} ${(g.member_ids || []).length}`}
                active={String(tab) === String(g.id)}
                onPress={() => setTab(g.id)}
                styles={styles}
              />
            ))}
          </View>
        </ScrollView>

        {visibleFriends.length === 0 ? (
          <Text style={styles.note}>Nobody in this group yet — add friends to it from the Friends tab.</Text>
        ) : (
          <View style={styles.card}>
            {visibleFriends.map((f, i) => {
              const on = selected.includes(f.id);
              const blocked = !on && (selected.length >= MAX_RIVALS || !canAddAnother);
              return (
                <Pressable
                  key={f.id}
                  onPress={() => !blocked && toggle(f.id)}
                  style={({ pressed }) => [
                    styles.person,
                    i < visibleFriends.length - 1 && styles.divider,
                    blocked && { opacity: 0.4 },
                    pressed && !blocked && { backgroundColor: colors.cardElevated },
                  ]}
                >
                  <View>
                    <Avatar name={f.username} size={38} />
                    {f.online ? <View style={styles.onlineDot} /> : null}
                  </View>
                  <Text style={styles.personName} numberOfLines={1}>
                    {f.username}
                  </Text>
                  <Ionicons
                    name={on ? 'checkmark-circle' : 'ellipse-outline'}
                    size={23}
                    color={on ? colors.accent : colors.placeholder}
                  />
                </Pressable>
              );
            })}
          </View>
        )}

        <Text style={styles.footnote}>
          {MAX_RIVALS} rivals max — {MAX_RIVALS + 1} drafters per duel. Everyone who accepts is in; you start when ready.
        </Text>

        {error ? <Text style={styles.error}>{error}</Text> : null}
      </ScrollView>

      <View style={styles.footer}>
        <View style={styles.summaryRow}>
          <Text style={styles.summary} numberOfLines={1}>
            {league.toUpperCase()} · {roster} slots · {clock}s clock
          </Text>
          <Text style={[styles.stakeOut, !stakeAffordable && { color: colors.danger }]}>{stakeLabel}</Text>
        </View>
        <Button
          title={cta}
          icon={selected.length ? 'send' : undefined}
          variant={selected.length ? 'primary' : 'outline'}
          onPress={send}
          loading={submitting}
          disabled={selected.length === 0 || !anyRosterFits}
        />
      </View>

      <RosterShapesModal
        visible={shapesOpen}
        onClose={() => setShapesOpen(false)}
        league={league}
        roster={roster}
        onPick={(size) => rosterOk(size) && setRoster(size)}
        rosterOk={rosterOk}
        styles={styles}
        colors={colors}
      />

      <CustomStakeModal
        visible={customOpen}
        onClose={closeCustom}
        value={customStake}
        onChange={setCustomStake}
        balance={balance}
        styles={styles}
        colors={colors}
      />
    </Screen>
  );
}

function StepLabel({ n, title, styles }) {
  return (
    <View style={styles.stepLabel}>
      <View style={styles.pip}>
        <Text style={styles.pipText}>{n}</Text>
      </View>
      <Text style={styles.stepTitle}>{title}</Text>
    </View>
  );
}

function Row({ label, children, styles, last, info, scroll }) {
  const inner = <View style={styles.opts}>{children}</View>;
  return (
    <View style={[styles.row, !last && styles.divider]}>
      <View style={styles.rowHead}>
        <Text style={styles.rowLabel}>{label}</Text>
        {info ? (
          <Pressable onPress={info} hitSlop={16} style={styles.infoBtn}>
            <Ionicons name="information" size={13} color="#0A0B10" />
          </Pressable>
        ) : null}
      </View>
      {scroll ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, flexShrink: 0 }}>
          {inner}
        </ScrollView>
      ) : (
        inner
      )}
    </View>
  );
}

function Opt({ label, active, disabled, onPress, styles }) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [styles.opt, active && styles.optActive, disabled && { opacity: 0.35 }, pressed && { opacity: 0.75 }]}
    >
      <Text style={[styles.optText, active && styles.optTextActive]}>{label}</Text>
    </Pressable>
  );
}

function Tab({ label, active, onPress, styles }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.tab, active && styles.tabActive, pressed && { opacity: 0.8 }]}>
      <Text style={[styles.tabText, active && styles.tabTextActive]}>{label}</Text>
    </Pressable>
  );
}

function RosterShapesModal({ visible, onClose, league, roster, onPick, rosterOk, styles, colors }) {
  const shapes = SHAPES[league] || {};
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <Text style={styles.sheetTitle}>ROSTER SHAPES</Text>
          <Text style={styles.sheetSub}>
            Positions lock as you draft. Shapes shown for {league.toUpperCase()}.
          </Text>
          {rosterSizesFor(league).map((size) => {
            const active = size === roster;
            const ok = rosterOk(size);
            return (
              <Pressable
                key={size}
                onPress={() => {
                  onPick(size);
                  onClose();
                }}
                disabled={!ok}
                style={[styles.shapeCard, active && styles.shapeCardActive, !ok && { opacity: 0.35 }]}
              >
                <Text style={[styles.shapeSize, active && { color: colors.accent }]}>{size} SLOTS</Text>
                <Text style={styles.shapeLine}>{(shapes[size] || []).join('  ·  ')}</Text>
                {!ok ? <Text style={styles.shapeWarn}>Not enough players on this slate</Text> : null}
              </Pressable>
            );
          })}
          <Button title="Done" variant="outline" onPress={onClose} style={{ marginTop: spacing.md }} />
        </Pressable>
      </Pressable>
    </Modal>
  );
}

function CustomStakeModal({ visible, onClose, value, onChange, balance, styles, colors }) {
  const n = parseInt(value, 10) || 0;
  const ok = n >= 1 && n <= balance;
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <Text style={styles.sheetTitle}>CUSTOM STAKE</Text>
          <Text style={styles.sheetSub}>Everyone puts in the same amount. You have ◎ {balance.toLocaleString()}.</Text>
          <TextInput
            value={value}
            onChangeText={(t) => onChange(t.replace(/[^0-9]/g, ''))}
            keyboardType="number-pad"
            placeholder="0"
            placeholderTextColor={colors.placeholder}
            style={styles.stakeInput}
            autoFocus
          />
          {value.length > 0 && !ok ? (
            <Text style={styles.shapeWarn}>{n > balance ? "That's more than you have." : 'Enter at least 1 coin.'}</Text>
          ) : null}
          <Button title="Set Stake" onPress={onClose} disabled={!ok} style={{ marginTop: spacing.md }} />
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    stepLabel: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: spacing.sm },
    stepRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.xl },
    pip: { width: 18, height: 18, borderRadius: 9, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center' },
    pipText: { color: '#0A0B10', fontSize: 11, fontFamily: fonts.bodyBlack },
    stepTitle: { color: colors.text, fontSize: 12, fontFamily: fonts.bodyExtra, letterSpacing: 2 },
    counter: { color: colors.muted, fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 1.5 },

    card: { backgroundColor: colors.card, borderRadius: 16, borderWidth: 1, borderColor: colors.border, overflow: 'hidden' },
    divider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.borderSubtle },

    row: { paddingHorizontal: 12, paddingVertical: 10 },
    rowHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 7 },
    rowLabel: { color: colors.muted, fontSize: 9.5, fontFamily: fonts.bodyExtra, letterSpacing: 2 },
    infoBtn: { width: 20, height: 20, borderRadius: 10, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center' },
    opts: { flexDirection: 'row', flexWrap: 'wrap', gap: 7 },

    opt: {
      minHeight: 36,
      paddingHorizontal: 14,
      justifyContent: 'center',
      borderRadius: 999,
      borderWidth: 1,
      borderColor: colors.border,
    },
    optActive: { backgroundColor: colors.accent, borderColor: colors.accent },
    optText: { color: colors.text, fontSize: 13, fontFamily: fonts.heroUpright, letterSpacing: 1 },
    optTextActive: { color: colors.onAccent },

    tabRow: { flexDirection: 'row', gap: 7, paddingVertical: spacing.sm },
    tab: { paddingHorizontal: 13, paddingVertical: 7, borderRadius: 999, borderWidth: 1, borderColor: colors.border },
    tabActive: { backgroundColor: colors.accent, borderColor: colors.accent },
    tabText: { color: colors.muted, fontSize: 11, fontFamily: fonts.bodyExtra, letterSpacing: 1 },
    tabTextActive: { color: colors.onAccent },

    person: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 12, paddingVertical: 9, minHeight: 56 },
    personName: { flex: 1, color: colors.text, fontSize: 15, fontFamily: fonts.bodyBold },
    onlineDot: {
      position: 'absolute',
      right: -1,
      bottom: -1,
      width: 11,
      height: 11,
      borderRadius: 6,
      backgroundColor: '#39D98A',
      borderWidth: 2,
      borderColor: colors.card,
    },

    note: { color: colors.muted, fontSize: 12, lineHeight: 18, marginTop: spacing.sm, fontFamily: fonts.body },
    footnote: { color: colors.placeholder, fontSize: 11, lineHeight: 17, marginTop: spacing.md, fontFamily: fonts.body },
    error: { color: colors.danger, fontSize: 13, marginTop: spacing.md, textAlign: 'center', fontFamily: fonts.bodyBold },

    footer: {
      position: 'absolute',
      left: 0,
      right: 0,
      bottom: 0,
      paddingHorizontal: spacing.lg,
      paddingTop: spacing.sm,
      paddingBottom: spacing.sm,
      backgroundColor: colors.bg,
      borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: colors.border,
    },
    summaryRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 7 },
    summary: { color: colors.muted, fontSize: 11, fontFamily: fonts.bodyExtra, letterSpacing: 1, flex: 1 },
    stakeOut: { color: colors.gold, fontSize: 12, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },

    backdrop: { flex: 1, backgroundColor: withAlpha('#000000', 0.65), justifyContent: 'center', padding: spacing.lg },
    sheet: { backgroundColor: colors.card, borderRadius: 18, borderWidth: 1, borderColor: colors.border, padding: spacing.lg },
    sheetTitle: { color: colors.text, fontSize: 15, fontFamily: fonts.heroUpright, letterSpacing: 1.5 },
    sheetSub: { color: colors.muted, fontSize: 12, lineHeight: 18, marginTop: 6, marginBottom: spacing.md, fontFamily: fonts.body },
    shapeCard: {
      borderRadius: 13,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
      padding: 13,
      marginBottom: spacing.sm,
    },
    shapeCardActive: { borderColor: colors.accent },
    shapeSize: { color: colors.text, fontSize: 13, fontFamily: fonts.heroUpright, letterSpacing: 1 },
    shapeLine: { color: colors.muted, fontSize: 12, marginTop: 4, fontFamily: fonts.condBold, letterSpacing: 0.5 },
    shapeWarn: { color: colors.danger, fontSize: 11, marginTop: 6, fontFamily: fonts.bodyBold },
    stakeInput: {
      color: colors.text,
      fontSize: 30,
      fontFamily: fonts.hero,
      textAlign: 'center',
      paddingVertical: 12,
      borderRadius: 13,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
    },
  });
```
