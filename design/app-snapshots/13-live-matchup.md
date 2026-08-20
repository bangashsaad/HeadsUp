# Live matchup — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

The head-to-head scoreboard for one duel: big total vs total with the lead, both rosters with each player's live fantasy line and game state, and the trash-talk thread (280 chars, same thread as web).

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

## The screen source (`src/screens/LiveMatchupScreen.js`)

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
import { ActivityIndicator, Animated, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getLiveResult, getMessages, sendMessage } from '../api/duels';
import { ApiError } from '../api/client';
import { notify, NotifyType } from '../haptics';
import { useTheme, useThemedStyles, spacing, font, fonts, withAlpha } from '../theme';
import { Screen, Card, Avatar, Badge, Button, GhostText, Kicker, CondTitle } from '../components/ui';
import PlayerAvatar from '../components/PlayerAvatar';
import TrashTalk from '../components/TrashTalk';

const pts = (v) => (Number(v) || 0).toFixed(1);

// Scale-bounces its children whenever `value` changes — the score just moved.
// `celebrate` adds a success haptic, but only when the number went UP.
function Pop({ value, celebrate = false, children }) {
  const scale = useRef(new Animated.Value(1)).current;
  const prev = useRef(value);

  useEffect(() => {
    if (prev.current === value) return;
    const up = value > prev.current;
    prev.current = value;
    if (celebrate && up) notify(NotifyType.Success);
    Animated.sequence([
      Animated.timing(scale, { toValue: 1.22, duration: 130, useNativeDriver: true }),
      Animated.spring(scale, { toValue: 1, friction: 4, useNativeDriver: true }),
    ]).start();
  }, [value, celebrate, scale]);

  return <Animated.View style={{ transform: [{ scale }] }}>{children}</Animated.View>;
}

// A player's game right now, as a tiny colored prefix on their stat line.
function gameTag(g, colors) {
  if (!g || !g.state) return null;
  if (g.state === 'in') return { label: (g.detail || 'LIVE').toUpperCase(), color: colors.danger };
  if (g.state === 'post') return { label: 'FINAL', color: colors.placeholder };
  if (g.state === 'pre') return { label: preLabel(g.detail), color: colors.muted };
  return null;
}

// ESPN's pre-game shortDetail is "7/9 - 7:00 PM EDT" — keep just the time.
function preLabel(detail) {
  if (!detail) return 'TIPS SOON';
  const t = detail.includes(' - ') ? detail.split(' - ').pop() : detail;
  return t.replace(/\s*E[DS]T\s*$/, ' ET').toUpperCase();
}

export default function LiveMatchupScreen({ route, navigation }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [live, setLive] = useState(null);
  const [error, setError] = useState(null);
  const timer = useRef(null);
  // Trash talk rides the same 15s tick as the score.
  const [chat, setChat] = useState([]);
  const [chatDraft, setChatDraft] = useState('');
  const [sending, setSending] = useState(false);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
        getMessages(token, id)
          .then((r) => active && setChat(r.messages || []))
          .catch(() => {});
        try {
          const res = await getLiveResult(token, id);
          if (active) setLive(res);
        } catch (e) {
          if (!active) return;
          // Settled while we watched → jump to the final result.
          if (e instanceof ApiError && e.status === 409) {
            navigation.replace('Results', { id, opponentName });
          } else if (!live) {
            setError(e.message);
          }
        }
      };
      tick();
      timer.current = setInterval(tick, 15000);
      return () => {
        active = false;
        if (timer.current) clearInterval(timer.current);
      };
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [token, id])
  );

  async function fireChat() {
    const body = chatDraft.trim();
    if (!body || sending) return;
    setSending(true);
    setChatDraft('');
    try {
      const res = await sendMessage(token, id, body);
      setChat((c) => [...c, res.message]);
    } catch (e) {
      setChatDraft(body); // give the jab back rather than eating it
    } finally {
      setSending(false);
    }
  }

  if (error && !live) {
    return (
      <Screen>
        <Card>
          <Text style={styles.note}>{error}</Text>
        </Card>
      </Screen>
    );
  }

  if (!live) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  const g = live.games || {};
  const isLive = (g.live || 0) > 0;
  const gameLine =
    [g.final ? `${g.final} FINAL` : null, g.live ? `${g.live} LIVE` : null, g.upcoming ? `${g.upcoming} TO TIP` : null]
      .filter(Boolean)
      .join(' · ') || 'NO GAMES IN THE WINDOW YET';

  // Group duel: ranked standings (sides arrive best-total-first).
  if (!live.challenger && (live.sides || []).length > 0) {
    const sides = live.sides;
    const myPlace = sides.findIndex((s) => s.is_me) + 1;

    function shareStandings() {
      Share.share({
        message: `My ${sides.length}-player Heads Up fantasy duel is live — I'm ${ordinal(myPlace)} of ${sides.length}! 🏀⚾️`,
      }).catch(() => {});
    }

    return (
      <Screen scroll>
        <Card padded={false}>
          <View style={styles.standHead}>
            <Kicker size={9} tracking={2}>
              Live standings
            </Kicker>
            {isLive ? <Badge label="Live" tone="danger" blink /> : null}
          </View>
          {sides.map((s, i) => (
            <Pressable
              key={s.user.id}
              disabled={s.is_me}
              onPress={() => navigation.navigate('UserProfile', { id: s.user.id, username: s.user.username })}
              style={({ pressed }) => [styles.standRow, i < sides.length - 1 && styles.playerDivider, pressed && { opacity: 0.7 }]}
            >
              <CondTitle size={16} color={i === 0 ? colors.accent : colors.placeholder} style={{ width: 22 }}>
                {i + 1}
              </CondTitle>
              <Avatar name={s.is_me ? 'You' : s.user.username} size={34} />
              <Text style={[styles.standName, s.is_me && { color: colors.accent }]} numberOfLines={1}>
                {s.is_me ? 'You' : s.user.username}
              </Text>
              <Pop value={Number(s.total) || 0} celebrate={s.is_me}>
                <CondTitle size={19} color={i === 0 ? colors.accent : colors.text}>
                  {pts(s.total)}
                </CondTitle>
              </Pop>
            </Pressable>
          ))}
        </Card>
        <Text style={styles.gamesLine}>{gameLine}</Text>

        {sides.map((s) => (
          <Five
            key={s.user.id}
            title={s.is_me ? 'YOUR SIDE' : `${(s.user.username || 'THEIR').toUpperCase()}'S SIDE`}
            side={s}
            mine={s.is_me}
            styles={styles}
            colors={colors}
          />
        ))}

        <Button title="Share matchup" icon="share-outline" variant="outline" onPress={shareStandings} style={{ marginTop: spacing.xl }} />
        <Text style={styles.note}>Live scoring — final standings are declared automatically once the games are final.</Text>
      </Screen>
    );
  }

  const me = live.challenger.is_me ? live.challenger : live.opponent;
  const them = live.challenger.is_me ? live.opponent : live.challenger;
  const meLeads = live.leader_id && me.user.id === live.leader_id;
  const themLead = live.leader_id && them.user.id === live.leader_id;
  const myT = Number(me.total) || 0;
  const opT = Number(them.total) || 0;
  const diff = myT - opT;
  const momPct = myT + opT <= 0 ? 50 : Math.max(8, Math.min(92, (myT / (myT + opT)) * 100));
  const leadText = diff === 0 ? 'DEAD EVEN' : diff > 0 ? `YOU LEAD BY ${diff.toFixed(1)}` : `DOWN ${Math.abs(diff).toFixed(1)} — RALLY TIME`;

  function shareMatchup() {
    const scoreLine = `${myT.toFixed(1)} to ${opT.toFixed(1)}`;
    const status = meLeads ? `I'm up ${scoreLine}` : themLead ? `I'm down ${scoreLine}` : `we're tied ${scoreLine}`;
    Share.share({
      message: `My Heads Up fantasy duel vs ${opponentName} is live — ${status}! 🏀⚾️`,
    }).catch(() => {});
  }

  return (
    <Screen scroll padded={false}>
      <View style={{ padding: spacing.lg, paddingBottom: spacing.xxl }}>
        {/* Scoreboard */}
        <LinearGradient colors={[colors.cardElevated, colors.card]} style={styles.scoreCard}>
          <View style={styles.scoreTop}>
            <Kicker size={9} tracking={2}>
              Head-to-head
            </Kicker>
            {isLive ? <Badge label="Live" tone="danger" blink /> : <Badge label="In play" tone="neutral" />}
          </View>
          <View style={styles.scoreRow}>
            <View>
              <Kicker size={10} tracking={1} color={colors.accent}>
                You
              </Kicker>
              <Pop value={myT} celebrate>
                <Text style={[styles.scoreBig, { color: myT >= opT ? colors.accent : colors.text }]}>{myT.toFixed(1)}</Text>
              </Pop>
            </View>
            <GhostText size={17} color={colors.textFaint} strokeWidth={1}>
              VS
            </GhostText>
            <View style={{ alignItems: 'flex-end' }}>
              <Kicker size={10} tracking={1} color={colors.purpleText}>
                {opponentName}
              </Kicker>
              <Pop value={opT}>
                <Text style={[styles.scoreBig, { color: opT > myT ? colors.purpleText : colors.text }]}>{opT.toFixed(1)}</Text>
              </Pop>
            </View>
          </View>
          <View style={styles.momTrack}>
            <LinearGradient
              colors={[withAlpha(colors.accent, 0.7), colors.accent]}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 0 }}
              style={[styles.momFill, { width: `${momPct}%` }]}
            />
          </View>
          <View style={styles.scoreFoot}>
            <Text style={styles.leadText}>{leadText}</Text>
            <Text style={styles.gamesFoot}>{gameLine}</Text>
          </View>
        </LinearGradient>

        <Five title="YOUR FIVE" side={me} mine styles={styles} colors={colors} />
        <Five title={`${opponentName.toUpperCase()}'S FIVE`} side={them} mine={false} styles={styles} colors={colors} />

        <TrashTalk chat={chat} draft={chatDraft} setDraft={setChatDraft} onSend={fireChat} sending={sending} />

        <Button title="Share matchup" icon="share-outline" variant="outline" onPress={shareMatchup} style={{ marginTop: spacing.xl }} />
        <Text style={styles.note}>Live scoring — the winner is declared automatically once the games are final.</Text>
      </View>
    </Screen>
  );
}

function ordinal(n) {
  return n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`;
}

// One side's roster panel: tinted header band, slot rows with stat lines.
function Five({ title, side, mine, styles, colors }) {
  const tint = mine ? colors.accent : colors.purpleText;
  const players = side.players || [];
  return (
    <View style={[styles.five, { borderColor: withAlpha(mine ? colors.accent : colors.purple, 0.35) }]}>
      <View style={[styles.fiveHead, { backgroundColor: withAlpha(mine ? colors.accent : colors.purple, 0.08) }]}>
        <Text style={[styles.fiveTitle, { color: tint }]}>{title}</Text>
      </View>
      {players.map((p, i) => {
        const tag = gameTag(p.game, colors);
        return (
          <View key={`${p.slot}-${p.player_id}`} style={[styles.playerRow, i > 0 && styles.playerTopBorder]}>
            <View style={styles.slotChip}>
              <Text style={styles.slotText}>{p.slot}</Text>
            </View>
            <PlayerAvatar uri={p.headshot_url} name={p.name || 'Player'} size={28} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.playerName} numberOfLines={1}>
                {p.name || 'Player'}
              </Text>
              <Text style={styles.statLine} numberOfLines={1}>
                {tag ? <Text style={{ color: tag.color, fontFamily: fonts.bodyBlack, fontSize: 10 }}>{`${tag.label} · `}</Text> : null}
                {p.line ? p.line : p.game?.state === 'pre' ? 'Waiting on tip' : 'Yet to check in'}
              </Text>
            </View>
            <Pop value={Number(p.points) || 0}>
              <Text style={[styles.points, { color: tint }]}>{pts(p.points)}</Text>
            </Pop>
          </View>
        );
      })}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    scoreCard: {
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      paddingHorizontal: 16,
      paddingTop: 14,
      paddingBottom: 12,
      overflow: 'hidden',
    },
    scoreTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    scoreRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 8 },
    scoreBig: { fontFamily: fonts.hero, fontSize: 46, lineHeight: 48, paddingRight: 4 },
    momTrack: { height: 7, borderRadius: 4, backgroundColor: withAlpha(colors.purple, 0.35), overflow: 'hidden', marginTop: 10 },
    momFill: { height: '100%', borderRadius: 4 },
    scoreFoot: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 6 },
    leadText: { fontSize: 9.5, fontFamily: fonts.bodyExtra, color: colors.muted },
    gamesFoot: { fontSize: 9.5, fontFamily: fonts.bodyBold, color: colors.placeholder },
    gamesLine: {
      color: colors.placeholder,
      fontSize: 10,
      fontFamily: fonts.bodyExtra,
      letterSpacing: 1,
      textAlign: 'center',
      marginTop: spacing.sm,
      marginBottom: spacing.xs,
    },
    five: { borderRadius: 13, borderWidth: 1, backgroundColor: colors.card, overflow: 'hidden', marginTop: spacing.md },
    fiveHead: { paddingVertical: 7, paddingHorizontal: 12 },
    fiveTitle: { fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1.5 },
    playerRow: { flexDirection: 'row', alignItems: 'center', gap: 9, paddingVertical: 8, paddingHorizontal: 12 },
    playerTopBorder: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    slotChip: { backgroundColor: colors.cardElevated, borderRadius: 5, paddingVertical: 2, minWidth: 34, alignItems: 'center' },
    slotText: { color: colors.muted, fontSize: 8.5, fontFamily: fonts.bodyBlack },
    playerName: { color: colors.text, fontSize: 13, fontFamily: fonts.bodyBold },
    statLine: { color: colors.muted, fontSize: 11.5, fontFamily: fonts.condBold, marginTop: 1, letterSpacing: 0.3 },
    points: { fontSize: 19, fontFamily: fonts.hero, minWidth: 48, textAlign: 'right' },
    standHead: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingTop: spacing.md,
      paddingBottom: spacing.xs,
      paddingHorizontal: spacing.lg,
    },
    standRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: 10, paddingHorizontal: spacing.lg },
    playerDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    standName: { color: colors.text, fontSize: font.body, fontFamily: fonts.bodyBold, flex: 1 },
    note: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.lg, lineHeight: 18, fontFamily: fonts.body },
  });
```

## Shared component it uses: `PlayerAvatar.js`

```jsx
import { useState } from 'react';
import { Image, View } from 'react-native';
import Avatar from './ui/Avatar';
import { useTheme } from '../theme';

// A player's face, with the initials Avatar as the fallback. Used anywhere a
// real athlete appears — draft board, rosters, live matchup, results.
//
// Falls back for two reasons: placeholder pools (NBA/NFL rows aren't seeded
// from ESPN yet, so they have no photo) and load failures. Either way the row
// looks deliberate rather than broken.
export default function PlayerAvatar({ uri, name, size = 36, style }) {
  const { colors } = useTheme();
  const [failed, setFailed] = useState(false);

  if (!uri || failed) return <Avatar name={name} size={size} style={style} />;

  return (
    <View
      style={[
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          overflow: 'hidden',
          backgroundColor: colors.cardElevated,
        },
        style,
      ]}
    >
      <Image
        source={{ uri }}
        style={{ width: size, height: size }}
        resizeMode="cover"
        onError={() => setFailed(true)}
      />
    </View>
  );
}
```

## Shared component it uses: `TrashTalk.js`

```jsx
import { KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { CondTitle, Kicker } from './ui';

// The rivalry's text thread — your jabs right-aligned in lime, theirs left in
// purple, capped input, send pill. One component so the live room and the
// post-game receipt argue in the same voice.
export default function TrashTalk({ chat, draft, setDraft, onSend, sending, title = 'TRASH TALK' }) {
  const { user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const myId = user?.id;

  return (
    <View style={styles.talkCard}>
      <View style={styles.talkHead}>
        <CondTitle size={15} color={colors.text} style={{ letterSpacing: 1 }}>
          {title}
        </CondTitle>
        <Kicker size={9} tracking={1.5}>
          Only the duel can see this
        </Kicker>
      </View>

      {chat.length === 0 ? (
        <Text style={styles.talkEmpty}>Say something. Scoreboard talk is free.</Text>
      ) : (
        <View style={styles.talkThread}>
          {chat.slice(-30).map((m) => {
            const mine = String(m.user_id) === String(myId);
            return (
              <View key={m.id} style={{ alignItems: mine ? 'flex-end' : 'flex-start' }}>
                <Text style={[styles.talkWho, { color: mine ? colors.accent : colors.purpleText }]}>
                  {mine ? 'YOU' : m.username.toUpperCase()}
                </Text>
                <View
                  style={[
                    styles.talkBubble,
                    mine
                      ? { backgroundColor: withAlpha(colors.accent, 0.1), borderColor: withAlpha(colors.accent, 0.35) }
                      : { backgroundColor: withAlpha(colors.purple, 0.12), borderColor: withAlpha(colors.purple, 0.4) },
                  ]}
                >
                  <Text style={styles.talkText}>{m.body}</Text>
                </View>
              </View>
            );
          })}
        </View>
      )}

      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={styles.talkRow}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            placeholder="Talk your talk…"
            placeholderTextColor={colors.placeholder}
            maxLength={280}
            style={styles.talkInput}
            onSubmitEditing={onSend}
            returnKeyType="send"
          />
          <Pressable
            onPress={onSend}
            disabled={sending || !draft.trim()}
            style={({ pressed }) => [
              styles.talkSend,
              (sending || !draft.trim()) && { opacity: 0.35 },
              pressed && { opacity: 0.7 },
            ]}
          >
            <Text style={{ color: colors.onAccent, fontFamily: fonts.bodyBlack, fontSize: 15 }}>➤</Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    talkCard: { marginTop: spacing.xl, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.card },
    talkHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md, paddingTop: spacing.md },
    talkEmpty: { color: colors.placeholder, fontSize: font.small, padding: spacing.md, textAlign: 'center' },
    talkThread: { padding: spacing.md, gap: 9 },
    talkWho: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1, marginBottom: 2 },
    talkBubble: { borderWidth: 1, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8, maxWidth: '80%' },
    talkText: { color: colors.text, fontSize: 13, lineHeight: 19 },
    talkRow: { flexDirection: 'row', gap: 8, padding: spacing.md, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.borderSubtle },
    talkInput: { flex: 1, backgroundColor: colors.bgElevated, borderWidth: 1, borderColor: colors.border, borderRadius: 999, paddingHorizontal: 15, paddingVertical: 10, color: colors.text, fontSize: 13, fontFamily: fonts.body },
    talkSend: { width: 40, height: 40, borderRadius: 999, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center' },
  });
```
