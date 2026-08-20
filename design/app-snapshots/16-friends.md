# Friends (FRIENDS tab) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Now its own TAB (tab bar: HOME · DUELS · DRAFT · LIVE · FRIENDS · YOU, with a cyan request-count bubble on the icon). Requests inline at the top as cyan ACCEPT/✕ cards, live username search (strangers appear as dashed "NOT IN YOUR CORNER YET" rows with + REQUEST / SENT ✓ / THEY ASKED — ACCEPT), group pills as filters, and every friend row: online dot, groups line, the series record vs you (lime lead / red trail / gray 0–0), a one-tap ⚔ DUEL into the composer, and a chevron into the rivalry page.

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

## The screen source (`src/screens/FriendsScreen.js`)

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
});import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, RefreshControl, ScrollView, Share, StyleSheet, Text, TextInput, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import {
  listFriends,
  listRequests,
  listFriendGroups,
  searchUsers,
  sendFriendRequest,
  acceptRequest,
  deleteRequest,
} from '../api/social';
import { getMyStats } from '../api/me';
import { setFriendReqs } from '../state/attention';
import { useTheme, useThemedStyles, avatarColor, spacing, fonts, withAlpha } from '../theme';
import { Screen, SkeletonList, EmptyState, Button } from '../components/ui';

// The FRIENDS tab, from Saad's Reimagined drop: requests inline at the top,
// search that surfaces strangers, group pills as filters, and every friend row
// carrying the series record vs you plus a one-tap ⚔ DUEL.
export default function FriendsScreen({ navigation }) {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [groups, setGroups] = useState([]);
  const [h2h, setH2h] = useState({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState(null);

  const [q, setQ] = useState('');
  const [results, setResults] = useState([]);
  const [sentIds, setSentIds] = useState(new Set());
  const [grp, setGrp] = useState('all');
  const debounce = useRef(null);

  const load = useCallback(async () => {
    try {
      const [f, r, g, s] = await Promise.all([
        listFriends(token),
        listRequests(token),
        listFriendGroups(token),
        getMyStats(token).catch(() => ({ head_to_head: [] })),
      ]);
      setFriends(f.friends);
      setRequests(r.requests);
      setGroups(g.groups || []);
      setH2h(Object.fromEntries((s.head_to_head || []).map((row) => [row.opponent.id, row])));
      setFriendReqs(r.requests.length);
      setLoadError(null);
    } catch (e) {
      // A dead network must not render as "nobody in your corner".
      setLoadError(e.message || 'Could not load your crew.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  // Debounced username search; two characters minimum, same as the server.
  useEffect(() => {
    if (debounce.current) clearTimeout(debounce.current);
    const trimmed = q.trim();
    if (trimmed.length < 2) {
      setResults([]);
      return;
    }
    debounce.current = setTimeout(() => {
      searchUsers(token, trimmed)
        .then((res) => setResults(res.users || []))
        .catch(() => {});
    }, 300);
    return () => clearTimeout(debounce.current);
  }, [q, token]);

  async function accept(friendshipId) {
    try {
      await acceptRequest(token, friendshipId);
    } catch (e) {
      Alert.alert("Couldn't accept that", e.message);
    }
    load();
  }

  async function decline(friendshipId) {
    try {
      await deleteRequest(token, friendshipId);
    } catch (e) {
      Alert.alert("Couldn't decline that", e.message);
    }
    load();
  }

  async function sendRequest(userId) {
    try {
      await sendFriendRequest(token, userId);
      setSentIds((prev) => new Set(prev).add(userId));
    } catch (e) {
      Alert.alert("Request didn't send", e.message);
    }
  }

  function openRivalry(f) {
    navigation.navigate('Rivalry', { id: f.id, username: f.username });
  }

  function challenge(id) {
    navigation.navigate('DuelsTab', { screen: 'CreateChallenge', params: { preselect: id }, initial: false });
  }

  function invite() {
    Share.share({ message: `Duel me on HeadsUp Fantasy — I'm ${user?.username}. First duel's on the house.` }).catch(() => {});
  }

  const frag = q.trim().toLowerCase();
  const inGroup = (f) => {
    if (grp === 'all') return true;
    const g = groups.find((x) => x.id === grp);
    return !!g && g.member_ids.includes(f.id);
  };
  const crew = friends.filter((f) => (!frag || f.username.toLowerCase().includes(frag)) && inGroup(f));
  const strangers = results.filter((r) => r.relationship !== 'friends');
  const noMatch = frag.length >= 2 && crew.length === 0 && strangers.length === 0;

  function recFor(f) {
    const r = h2h[f.id];
    if (!r || r.played === 0) return { text: '0–0', color: colors.placeholder };
    if (r.wins > r.losses) return { text: `${r.wins}–${r.losses}`, color: colors.accent };
    if (r.wins < r.losses) return { text: `${r.wins}–${r.losses}`, color: colors.danger };
    return { text: `${r.wins}–${r.losses}`, color: colors.muted };
  }

  function subFor(f) {
    const names = groups.filter((g) => g.member_ids.includes(f.id)).map((g) => g.name);
    if (names.length) return names.join(' · ');
    const r = h2h[f.id];
    return r && r.played > 0 ? 'No groups yet' : 'New · never played';
  }

  if (loading) {
    return (
      <Screen edges={['top']}>
        <SkeletonList count={7} />
      </Screen>
    );
  }

  if (loadError && friends.length === 0 && requests.length === 0) {
    return (
      <Screen edges={['top']}>
        <EmptyState
          icon="cloud-offline-outline"
          title="Couldn't reach the server"
          subtitle={loadError}
          action={<Button title="Try again" icon="refresh" onPress={() => { setLoading(true); load(); }} />}
        />
      </Screen>
    );
  }

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: spacing.xxl }}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor={colors.accent} />
        }
      >
        <LinearGradient
          colors={[withAlpha(colors.purple, 0.18), 'transparent']}
          start={{ x: 0.2, y: 0 }}
          end={{ x: 0.6, y: 1 }}
          style={styles.headerZone}
        >
          <View style={styles.titleRow}>
            <Text style={styles.title}>FRIENDS</Text>
            <Text style={styles.counter}>{friends.length} IN YOUR CORNER</Text>
          </View>
          <View style={styles.searchPill}>
            <Ionicons name="search" size={14} color={colors.placeholder} />
            <TextInput
              style={styles.searchInput}
              value={q}
              onChangeText={setQ}
              placeholder="Search usernames…"
              placeholderTextColor={colors.placeholder}
              autoCapitalize="none"
              autoCorrect={false}
            />
            {q !== '' && (
              <Pressable onPress={() => setQ('')} hitSlop={8}>
                <Ionicons name="close-circle" size={16} color={colors.placeholder} />
              </Pressable>
            )}
          </View>
        </LinearGradient>

        {requests.length > 0 && (
          <View style={styles.section}>
            <View style={styles.reqHead}>
              <Text style={styles.reqLabel}>REQUESTS</Text>
              <View style={styles.reqCount}>
                <Text style={styles.reqCountText}>{requests.length}</Text>
              </View>
            </View>
            {requests.map((r) => {
              const tint = avatarColor(r.user.username);
              return (
                <View key={r.id} style={styles.reqCard}>
                  <View style={[styles.avatar, { width: 32, height: 32, borderRadius: 10, backgroundColor: tint + '22', borderColor: tint + '55' }]}>
                    <Text style={[styles.avatarText, { color: tint, fontSize: 12 }]}>{r.user.username[0].toUpperCase()}</Text>
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.rowName} numberOfLines={1}>{r.user.username}</Text>
                    <Text style={styles.wantsIn}>WANTS IN</Text>
                  </View>
                  <Pressable onPress={() => accept(r.id)} style={({ pressed }) => [styles.acceptPill, pressed && styles.pressed]}>
                    <Text style={styles.acceptText}>ACCEPT</Text>
                  </Pressable>
                  <Pressable onPress={() => decline(r.id)} style={({ pressed }) => [styles.declineCircle, pressed && styles.pressed]}>
                    <Text style={styles.declineX}>✕</Text>
                  </Pressable>
                </View>
              );
            })}
          </View>
        )}

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0 }} contentContainerStyle={styles.tabsRow}>
          {groups.length > 0 &&
            [{ id: 'all', name: 'ALL' }, ...groups].map((g) => {
              const on = grp === g.id;
              const n = g.id === 'all' ? friends.length : g.member_ids.length;
              return (
                <Pressable
                  key={g.id}
                  onPress={() => setGrp(g.id)}
                  style={[styles.tabPill, on && { borderColor: colors.purple, backgroundColor: withAlpha(colors.purple, 0.15) }]}
                >
                  <Text style={[styles.tabText, on && { color: colors.purpleText }]}>
                    {g.name} <Text style={{ opacity: 0.6 }}>{n}</Text>
                  </Text>
                </Pressable>
              );
            })}
          <Pressable
            onPress={() => navigation.navigate('FriendGroups')}
            style={[styles.tabPill, { borderStyle: 'dashed', borderColor: withAlpha(colors.purple, 0.5) }]}
          >
            <Text style={[styles.tabText, { color: colors.purpleText }]}>
              {groups.length > 0 ? '⚙ GROUPS' : '＋ NEW GROUP'}
            </Text>
          </Pressable>
        </ScrollView>

        <View style={styles.section}>
          {crew.map((f) => {
            const tint = avatarColor(f.username);
            const rec = recFor(f);
            return (
              <Pressable key={f.id} onPress={() => openRivalry(f)} style={({ pressed }) => [styles.row, pressed && styles.pressed]}>
                <View style={{ position: 'relative' }}>
                  <View style={[styles.avatar, { backgroundColor: tint + '22', borderColor: tint + '55' }]}>
                    <Text style={[styles.avatarText, { color: tint }]}>{f.username[0].toUpperCase()}</Text>
                  </View>
                  {f.online && <View style={styles.onlineDot} />}
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={styles.rowName} numberOfLines={1}>{f.username}</Text>
                  <Text style={styles.rowSub} numberOfLines={1}>{subFor(f)}</Text>
                </View>
                <Text style={[styles.rec, { color: rec.color }]}>{rec.text}</Text>
                <Pressable
                  onPress={(e) => { e.stopPropagation && e.stopPropagation(); challenge(f.id); }}
                  style={({ pressed }) => [styles.duelPill, pressed && styles.pressed]}
                >
                  <Text style={styles.duelText}>⚔ DUEL</Text>
                </Pressable>
                <Text style={styles.chevron}>›</Text>
              </Pressable>
            );
          })}

          {friends.length === 0 && frag.length < 2 && (
            <EmptyState
              icon="people-outline"
              title="Nobody in your corner yet"
              subtitle="Search a username above, or send an invite — first duel's on the house."
              action={<Button title="Invite a friend" icon="share-outline" onPress={invite} />}
            />
          )}
        </View>

        {strangers.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.strangerLabel}>NOT IN YOUR CORNER YET</Text>
            {strangers.map((s) => {
              const sent = s.relationship === 'request_sent' || sentIds.has(s.id);
              const askedFirst = s.relationship === 'request_received';
              return (
                <View key={s.id} style={styles.strangerRow}>
                  <View style={[styles.avatar, { backgroundColor: colors.borderSubtle, borderColor: colors.border }]}>
                    <Text style={[styles.avatarText, { color: colors.muted }]}>{s.username[0].toUpperCase()}</Text>
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.rowName} numberOfLines={1}>{s.username}</Text>
                    <Text style={styles.rowSub} numberOfLines={1}>{s.meta || 'new here'}</Text>
                  </View>
                  {askedFirst ? (
                    <Pressable onPress={() => accept(s.friendship_id)} style={({ pressed }) => [styles.requestPill, pressed && styles.pressed]}>
                      <Text style={styles.requestText}>THEY ASKED — ACCEPT</Text>
                    </Pressable>
                  ) : sent ? (
                    <View style={styles.sentPill}>
                      <Text style={styles.sentText}>SENT ✓</Text>
                    </View>
                  ) : (
                    <Pressable onPress={() => sendRequest(s.id)} style={({ pressed }) => [styles.requestPill, pressed && styles.pressed]}>
                      <Text style={styles.requestText}>+ REQUEST</Text>
                    </Pressable>
                  )}
                </View>
              );
            })}
          </View>
        )}

        {noMatch && (
          <Pressable onPress={invite} style={styles.noMatch}>
            <Text style={styles.noMatchTitle}>NOBODY BY THAT NAME</Text>
            <Text style={styles.noMatchSub}>Send them an invite link — first duel's on the house.</Text>
          </Pressable>
        )}
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.md },
    titleRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between' },
    title: { fontFamily: fonts.display, fontSize: 24, letterSpacing: -0.5, color: colors.text },
    counter: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1, color: colors.placeholder },
    searchPill: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingHorizontal: 14,
      paddingVertical: 10,
      marginTop: 12,
    },
    searchInput: { flex: 1, minWidth: 0, color: colors.text, fontFamily: fonts.body, fontSize: 13, padding: 0 },
    section: { paddingHorizontal: spacing.lg, paddingTop: spacing.md, gap: 7 },
    reqHead: { flexDirection: 'row', alignItems: 'center', gap: 7 },
    reqLabel: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.cyan },
    reqCount: { backgroundColor: colors.cyan, borderRadius: 999, paddingHorizontal: 7, paddingVertical: 1 },
    reqCountText: { color: '#0A0B10', fontSize: 9, fontFamily: fonts.bodyBlack },
    reqCard: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: withAlpha(colors.cyan, 0.35),
      backgroundColor: withAlpha(colors.cyan, 0.05),
      paddingHorizontal: 12,
      paddingVertical: 10,
    },
    avatar: {
      width: 34,
      height: 34,
      borderRadius: 11,
      borderWidth: 1,
      alignItems: 'center',
      justifyContent: 'center',
      flexShrink: 0,
    },
    avatarText: { fontFamily: fonts.bodyExtra, fontSize: 13 },
    onlineDot: {
      position: 'absolute',
      right: -2,
      bottom: -2,
      width: 9,
      height: 9,
      borderRadius: 5,
      backgroundColor: colors.green,
      borderWidth: 2,
      borderColor: colors.bg,
    },
    rowName: { fontSize: 13, fontFamily: fonts.bodyBold, color: colors.text },
    rowSub: { fontSize: 10, color: colors.muted, marginTop: 1 },
    wantsIn: { fontSize: 9.5, fontFamily: fonts.bodyExtra, color: colors.cyan, marginTop: 1 },
    acceptPill: { backgroundColor: colors.accent, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 7 },
    acceptText: { color: colors.onAccent, fontFamily: fonts.hero, fontSize: 13 },
    declineCircle: {
      width: 30,
      height: 30,
      borderRadius: 15,
      borderWidth: 1,
      borderColor: colors.border,
      alignItems: 'center',
      justifyContent: 'center',
    },
    declineX: { color: colors.muted, fontSize: 13, fontFamily: fonts.bodyExtra },
    tabsRow: { gap: 6, paddingHorizontal: spacing.lg, paddingTop: spacing.lg },
    tabPill: {
      borderRadius: 999,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      paddingHorizontal: 13,
      paddingVertical: 7,
    },
    tabText: { fontFamily: fonts.heroUpright, fontSize: 12.5, letterSpacing: 1, color: colors.muted, lineHeight: 16 },
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
      paddingHorizontal: 12,
      paddingVertical: 10,
    },
    rec: { fontFamily: fonts.hero, fontSize: 16, flexShrink: 0 },
    duelPill: {
      borderWidth: 1,
      borderColor: withAlpha(colors.accent, 0.6),
      borderRadius: 999,
      paddingHorizontal: 12,
      paddingVertical: 6,
      flexShrink: 0,
    },
    duelText: { color: colors.accent, fontFamily: fonts.hero, fontSize: 12.5 },
    chevron: { color: colors.textFaint, fontSize: 14, fontFamily: fonts.bodyBold, flexShrink: 0 },
    strangerLabel: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.placeholder },
    strangerRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      borderRadius: 12,
      borderWidth: 1,
      borderStyle: 'dashed',
      borderColor: colors.textFaint,
      backgroundColor: colors.bgElevated,
      paddingHorizontal: 12,
      paddingVertical: 10,
    },
    requestPill: { backgroundColor: colors.accent, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 7, flexShrink: 0 },
    requestText: { color: colors.onAccent, fontFamily: fonts.hero, fontSize: 12.5 },
    sentPill: {
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingHorizontal: 14,
      paddingVertical: 7,
      flexShrink: 0,
    },
    sentText: { color: colors.placeholder, fontFamily: fonts.hero, fontSize: 12.5 },
    noMatch: { paddingVertical: 30, paddingHorizontal: spacing.lg, alignItems: 'center', gap: 6 },
    noMatchTitle: { fontFamily: fonts.hero, fontSize: 19, color: colors.muted, letterSpacing: 1 },
    noMatchSub: { fontSize: 11, color: colors.placeholder, fontFamily: fonts.bodySemi },
    pressed: { opacity: 0.85, transform: [{ scale: 0.985 }] },
  });
```
