# Profile (YOU tab) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Your card: record hero (W–L, streak, win rate), splits, YOUR CREW (friends with per-rival head-to-head), WANTS IN requests inbox, friend groups, and the account rows (coin wallet, verify email, settings, change password, sign out, delete account).

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

## The screen source (`src/screens/ProfileScreen.js`)

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
import { Alert, Modal, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getMyStats, getAchievements, getLeaderboard } from '../api/me';
import { listRequests } from '../api/social';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { Screen, Card, Avatar, Button, StatTile, SectionHeader, CondTitle, Kicker } from '../components/ui';

function Row({ icon, label, sublabel, onPress, danger, count }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
      <View style={[styles.rowIcon, danger && { backgroundColor: colors.dangerSoft }]}>
        <Ionicons name={icon} size={18} color={danger ? colors.danger : colors.accent} />
      </View>
      <View style={{ flex: 1 }}>
        <Text style={[styles.rowLabel, danger && { color: colors.danger }]}>{label}</Text>
        {sublabel ? <Text style={styles.rowSub}>{sublabel}</Text> : null}
      </View>
      {count > 0 ? (
        <View style={styles.rowCount}>
          <Text style={styles.rowCountText}>{count}</Text>
        </View>
      ) : null}
      <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
    </Pressable>
  );
}

const RANK_COLOR = (colors, rank) =>
  rank === 1 ? colors.gold : rank === 2 ? colors.silver : rank === 3 ? colors.bronze : colors.placeholder;

export default function ProfileScreen({ navigation }) {
  const { user, token, signOut, refreshUser } = useAuth();
  const { colors, scheme } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [stats, setStats] = useState(null);
  const [trophies, setTrophies] = useState([]);
  const [standings, setStandings] = useState([]);
  const [requestCount, setRequestCount] = useState(0);
  const [openTrophy, setOpenTrophy] = useState(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      refreshUser(); // keep the coin balance honest whenever YOU opens
      getMyStats(token)
        .then((s) => active && setStats(s))
        .catch(() => {});
      getAchievements(token)
        .then((r) => active && setTrophies(r.achievements || []))
        .catch(() => {});
      getLeaderboard(token)
        .then((r) => active && setStandings(r.leaderboard || []))
        .catch(() => {});
      listRequests(token)
        .then((r) => active && setRequestCount((r.requests || []).length))
        .catch(() => {});
      return () => {
        active = false;
      };
    }, [token])
  );

  function invite() {
    Share.share({
      message: `Play me 1-on-1 in Heads Up fantasy 🏀⚾️ — draft a lineup, winner takes bragging rights. Add me: my username is ${user?.username}.`,
    }).catch(() => {});
  }

  function howToPlay() {
    Alert.alert(
      'How to play',
      'Challenge a friend to a 1-on-1 fantasy duel — or invite up to 3 for a group match. Agree on the sport, lineup and scoring, draft your rosters live (snake order, ticking clock), then the winner is declared automatically once the games finish. Best total takes it.'
    );
  }

  const rec = stats?.record;
  const h2h = stats?.head_to_head || [];
  const h2hById = new Map(h2h.map((r) => [String(r.opponent.id), r]));
  const winPct = rec ? Math.round((rec.win_pct || 0) * (rec.win_pct <= 1 ? 100 : 1)) : null;
  const ptDiff = rec ? Math.round(((rec.points_for || 0) - (rec.points_against || 0)) * 10) / 10 : 0;
  const myRank = standings.find((r) => String(r.user?.id) === String(user?.id))?.rank;
  const earned = trophies.filter((t) => t.earned).length;

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView contentContainerStyle={{ paddingBottom: spacing.xxl }} showsVerticalScrollIndicator={false}>
        {/* Identity. The cyan glow is a dark-mode device; light stays clean. */}
        <LinearGradient
          colors={scheme === 'dark' ? [withAlpha(colors.cyan, 0.12), 'transparent'] : ['transparent', 'transparent']}
          start={{ x: 0.8, y: 0 }}
          end={{ x: 0.4, y: 1 }}
          style={styles.headerZone}
        >
          <View style={styles.idRow}>
            <Avatar name={user?.username || '?'} size={62} />
            <View style={{ flex: 1 }}>
              <CondTitle size={26} numberOfLines={1} style={{ paddingRight: 4 }}>
                {(user?.username || '?').toUpperCase()}
              </CondTitle>
              <View style={styles.chipRow}>
                <Pressable onPress={() => navigation.navigate('CoinHistory')} style={[styles.idChip, styles.coinChip]}>
                  <Text style={[styles.idChipText, { color: colors.gold }]}>◎ {(user?.coins ?? 0).toLocaleString()}</Text>
                </Pressable>
                {rec?.streak?.count > 0 ? (
                  <View style={styles.idChip}>
                    <Text
                      style={[
                        styles.idChipText,
                        { color: rec.streak.type === 'win' ? colors.gold : rec.streak.type === 'loss' ? colors.danger : colors.muted },
                      ]}
                    >
                      {rec.streak.type === 'win' ? `🔥 W${rec.streak.count} STREAK` : `${rec.streak.type[0].toUpperCase()}${rec.streak.count} STREAK`}
                    </Text>
                  </View>
                ) : null}
                {myRank ? (
                  <View style={styles.idChip}>
                    <Text style={[styles.idChipText, { color: colors.muted }]}>#{myRank} OF FRIENDS</Text>
                  </View>
                ) : null}
              </View>
            </View>
          </View>

          <View style={styles.statGrid}>
            <StatTile value={rec?.wins ?? 0} label="Wins" color={colors.accent} />
            <StatTile value={rec?.losses ?? 0} label="Losses" color={colors.danger} />
            <StatTile value={winPct != null ? `${winPct}%` : '—'} label="Win rate" />
            <StatTile value={`${ptDiff >= 0 ? '+' : ''}${ptDiff}`} label="Pt diff" />
          </View>
        </LinearGradient>

        <View style={{ paddingHorizontal: spacing.lg }}>
          {/* Trophy case */}
          {trophies.length > 0 ? (
            <SectionHeader hint={`${earned} / ${trophies.length}`}>Trophy case</SectionHeader>
          ) : null}
        </View>
        {trophies.length > 0 ? (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.trophyRow}>
            {trophies.map((t) => (
              <Pressable
                key={t.key}
                onPress={() => setOpenTrophy(t)}
                style={({ pressed }) => [styles.trophyTile, t.earned ? styles.trophyTileOn : styles.trophyTileOff, pressed && { opacity: 0.8 }]}
              >
                <Ionicons name={t.icon} size={21} color={t.earned ? colors.accent : colors.placeholder} />
                <Text style={[styles.trophyTitle, !t.earned && { color: colors.muted }]} numberOfLines={1}>
                  {t.title}
                </Text>
                <Text style={styles.trophySub} numberOfLines={1}>
                  {t.earned ? '✓ EARNED' : `${Math.min(t.value, t.threshold)}/${t.threshold}`}
                </Text>
              </Pressable>
            ))}
          </ScrollView>
        ) : null}

        <View style={{ paddingHorizontal: spacing.lg }}>
          {/* Standings among friends */}
          <SectionHeader hint={requestCount > 0 ? `${requestCount} REQUEST${requestCount > 1 ? 'S' : ''}` : undefined}>
            Friend standings
          </SectionHeader>
          {standings.length === 0 ? (
            <Card>
              <Text style={styles.emptyStandings}>No friends yet. Add some and the standings show up here.</Text>
              <Button title="Add friends" size="sm" full={false} style={{ marginTop: spacing.md, alignSelf: 'flex-start' }} onPress={() => navigation.navigate('FriendsTab')} />
            </Card>
          ) : (
            <View style={{ gap: 7 }}>
              {standings.map((r) => {
                const isMe = String(r.user?.id) === String(user?.id);
                const vs = h2hById.get(String(r.user?.id));
                return (
                  <Pressable
                    key={r.user?.id ?? r.rank}
                    disabled={isMe}
                    onPress={() => navigation.navigate('FriendsTab', { screen: 'Rivalry', params: { id: r.user.id, username: r.user.username }, initial: false })}
                    style={({ pressed }) => [styles.standingRow, isMe && styles.standingRowMe, pressed && { opacity: 0.8 }]}
                  >
                    <CondTitle size={15} color={RANK_COLOR(colors, r.rank)} style={{ width: 20 }}>
                      {r.rank}
                    </CondTitle>
                    <Avatar name={isMe ? user?.username : r.user?.username} size={30} />
                    <View style={{ flex: 1 }}>
                      <Text style={[styles.standingName, isMe && { color: colors.accent }]} numberOfLines={1}>
                        {isMe ? `${user?.username} · you` : r.user?.username}
                      </Text>
                      <Text style={styles.standingSub} numberOfLines={1}>
                        {isMe
                          ? myRank === 1
                            ? 'Top of the standings — defend it'
                            : 'Climb the board — win a duel'
                          : vs
                            ? `Your record vs: ${vs.wins}–${vs.losses}${vs.ties ? `–${vs.ties}` : ''}`
                            : 'No duels yet — call them out'}
                      </Text>
                    </View>
                    <Text style={styles.standingRec}>
                      {r.wins}–{r.losses}
                      {r.ties ? `–${r.ties}` : ''}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          )}

          {/* Menu */}
          <Card padded={false} style={{ marginTop: spacing.lg }}>
            <Row
              icon="people-outline"
              label="Friends & groups"
              sublabel="Crew, requests, rivalries — the FRIENDS tab"
              count={requestCount}
              onPress={() => navigation.navigate('FriendsTab')}
            />
            <View style={styles.menuDivider} />
            <Row icon="person-add-outline" label="Invite a friend" sublabel="Share your username to duel" onPress={invite} />
            <View style={styles.menuDivider} />
            <Row
              icon="server-outline"
              label="Coin wallet"
              sublabel={`◎ ${(user?.coins ?? 0).toLocaleString()} — stakes, pots & bonuses`}
              onPress={() => navigation.navigate('CoinHistory')}
            />
            <View style={styles.menuDivider} />
            <Row icon="settings-outline" label="Settings" sublabel="Appearance, preferences, account" onPress={() => navigation.navigate('Settings')} />
            <View style={styles.menuDivider} />
            <Row icon="help-circle-outline" label="How to play" onPress={howToPlay} />
          </Card>

          <View style={{ marginTop: spacing.xl }}>
            <Button title="Log out" variant="danger" icon="log-out-outline" onPress={signOut} />
          </View>
        </View>
      </ScrollView>

      <TrophySheet trophy={openTrophy} onClose={() => setOpenTrophy(null)} styles={styles} colors={colors} />
    </Screen>
  );
}

// Tap a trophy → what it means and how close you are.
function TrophySheet({ trophy, onClose, styles, colors }) {
  if (!trophy) return null;
  const earned = trophy.earned;
  const progress = Math.min(trophy.value / Math.max(trophy.threshold, 1), 1);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.sheetWrap}>
        <Pressable style={styles.sheetBackdrop} onPress={onClose} />
        <View style={styles.sheet}>
          <View style={styles.sheetHandle} />
          <View
            style={[
              styles.sheetTrophyIcon,
              { backgroundColor: earned ? colors.accentSoft : colors.card, borderColor: earned ? colors.accentBorder : colors.border },
            ]}
          >
            <Ionicons name={trophy.icon} size={34} color={earned ? colors.accent : colors.placeholder} />
          </View>
          <CondTitle size={24} style={{ marginTop: spacing.md }}>
            {trophy.title.toUpperCase()}
          </CondTitle>
          <Text style={styles.sheetDesc}>{trophy.description}</Text>

          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${Math.round(progress * 100)}%`, backgroundColor: earned ? colors.accent : colors.muted }]} />
          </View>
          <Kicker size={11} tracking={1} color={earned ? colors.accent : colors.muted} style={{ marginTop: spacing.sm }}>
            {earned ? '✓ Earned' : `${Math.min(trophy.value, trophy.threshold)} of ${trophy.threshold}`}
          </Kicker>
        </View>
      </View>
    </Modal>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
    idRow: { flexDirection: 'row', alignItems: 'center', gap: 14 },
    chipRow: { flexDirection: 'row', gap: 6, marginTop: 6 },
    idChip: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingVertical: 3,
      paddingHorizontal: 9,
    },
    idChipText: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    coinChip: { borderColor: withAlpha(colors.gold, 0.45), backgroundColor: withAlpha(colors.gold, 0.1) },
    statGrid: { flexDirection: 'row', gap: 8, marginTop: spacing.lg },
    trophyRow: { gap: 8, paddingHorizontal: spacing.lg },
    trophyTile: {
      width: 86,
      borderRadius: 12,
      borderWidth: 1,
      paddingVertical: 10,
      alignItems: 'center',
      gap: 5,
    },
    trophyTileOn: { borderColor: withAlpha(colors.accent, 0.4), backgroundColor: withAlpha(colors.accent, 0.08) },
    trophyTileOff: { borderColor: colors.border, backgroundColor: colors.card, opacity: 0.55 },
    trophyTitle: { color: colors.text, fontSize: 9, fontFamily: fonts.bodyExtra, maxWidth: 78, textAlign: 'center' },
    trophySub: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
    emptyStandings: { color: colors.muted, fontSize: font.small, lineHeight: 19, fontFamily: fonts.body },
    standingRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
      paddingVertical: 10,
      paddingHorizontal: 12,
    },
    standingRowMe: { backgroundColor: withAlpha(colors.accent, 0.06), borderColor: withAlpha(colors.accent, 0.45) },
    standingName: { color: colors.text, fontSize: 13, fontFamily: fonts.bodyBold },
    standingSub: { color: colors.muted, fontSize: 10, marginTop: 1, fontFamily: fonts.body },
    standingRec: { color: colors.text, fontFamily: fonts.heroUpright, fontSize: 15 },
    row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    rowIcon: { width: 34, height: 34, borderRadius: 10, backgroundColor: colors.accentSoft, alignItems: 'center', justifyContent: 'center', marginRight: spacing.md },
    rowLabel: { color: colors.text, fontSize: font.bodyLg, fontFamily: fonts.bodySemi },
    rowSub: { color: colors.muted, fontSize: font.small, marginTop: 1, fontFamily: fonts.body },
    rowCount: {
      minWidth: 20,
      height: 20,
      borderRadius: 10,
      backgroundColor: colors.danger,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 5,
      marginRight: 6,
    },
    rowCountText: { color: '#fff', fontSize: 11, fontFamily: fonts.bodyExtra },
    menuDivider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle, marginLeft: 60 },
    sheetWrap: { flex: 1, justifyContent: 'flex-end' },
    sheetBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.55)' },
    sheet: {
      backgroundColor: colors.bg,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
      borderWidth: 1,
      borderColor: colors.border,
      padding: spacing.xl,
      paddingBottom: spacing.xxl,
      alignItems: 'center',
    },
    sheetHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.border, marginBottom: spacing.lg },
    sheetTrophyIcon: { width: 72, height: 72, borderRadius: 22, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
    sheetDesc: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.xs, lineHeight: 21, fontFamily: fonts.body },
    progressTrack: { alignSelf: 'stretch', height: 8, borderRadius: 4, backgroundColor: colors.bgElevated, marginTop: spacing.lg, overflow: 'hidden' },
    progressFill: { height: 8, borderRadius: 4 },
  });
```
