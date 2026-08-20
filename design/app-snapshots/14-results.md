# Results / receipt — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

The settled duel: W/L/T verdict (YOU WIN. energy, confetti on a W), coin swing, final totals, per-player scoring breakdown for both sides, REMATCH · SAME TERMS.

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

## The screen source (`src/screens/ResultsScreen.js`)

```jsx
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Animated, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getMessages, getResult, rematch, sendMessage } from '../api/duels';
import { ApiError } from '../api/client';
import ConfettiBurst from '../components/ConfettiBurst';
import { notify, NotifyType } from '../haptics';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { Screen, Card, Avatar, Button, EmptyState, GhostText, Kicker, DisplayTitle, CondTitle, Pulse } from '../components/ui';
import PlayerAvatar from '../components/PlayerAvatar';
import TrashTalk from '../components/TrashTalk';

const ordinal = (n) => (n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`);
const medal = (rank) => (rank === 1 ? '🥇' : rank === 2 ? '🥈' : rank === 3 ? '🥉' : String(rank));
const pn = (v) => Number(v) || 0;

function groupBanner(rank, tiedTop) {
  if (rank === 1 && tiedTop) return { title: 'DEAD HEAT', color: 'text', sub: 'Tied for the top spot. Run it back.' };
  if (rank === 1) return { title: 'CHAMPION.', color: 'accent', sub: 'Top of the pile. Send them the receipt.' };
  return { title: `${ordinal(rank).toUpperCase()} PLACE`, color: rank <= 3 ? 'text' : 'danger', sub: 'Not your night. Instant rematch?' };
}

// Ease a number from 0 to target on mount (easeOutCubic).
function useCountUp(target, duration = 850) {
  const [val, setVal] = useState(0);
  useEffect(() => {
    let raf;
    let start;
    const tick = (t) => {
      if (start == null) start = t;
      const p = Math.min(1, (t - start) / duration);
      setVal(target * (1 - Math.pow(1 - p, 3)));
      if (p < 1) raf = requestAnimationFrame(tick);
      else setVal(target);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target, duration]);
  return val;
}

function topStats(statLine) {
  const entries = Object.entries(statLine || {}).filter(([, v]) => v);
  if (entries.length === 0) return 'did not play';
  return entries
    .slice(0, 4)
    .map(([k, v]) => `${v} ${k.replace(/_/g, ' ')}`)
    .join(' · ');
}

export default function ResultsScreen({ route, navigation }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token, refreshUser } = useAuth();
  const { colors, scheme } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [result, setResult] = useState(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(null);
  const celebrated = useRef(false);
  const pop = useRef(new Animated.Value(0.85)).current;
  const [rematching, setRematching] = useState(false);
  const [confetti, setConfetti] = useState(false);
  // The thread carries over from the live room — receipts stay open.
  const [chat, setChat] = useState([]);
  const [chatDraft, setChatDraft] = useState('');
  const [sendingChat, setSendingChat] = useState(false);

  async function doRematch() {
    setRematching(true);
    try {
      const res = await rematch(token, id);
      navigation.navigate('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setRematching(false);
      Alert.alert("Couldn't rematch", e.message);
    }
  }

  useFocusEffect(
    useCallback(() => {
      let active = true;
      (async () => {
        setPending(false);
        setError(null);
        try {
          const res = await getResult(token, id);
          if (active) setResult(res.result);
        } catch (e) {
          if (!active) return;
          if (e instanceof ApiError && e.status === 404) setPending(true);
          else setError(e.message);
        }
      })();
      const loadChat = () =>
        getMessages(token, id)
          .then((r) => active && setChat(r.messages || []))
          .catch(() => {});
      loadChat();
      const chatTimer = setInterval(loadChat, 20000);
      return () => {
        active = false;
        clearInterval(chatTimer);
      };
    }, [token, id])
  );

  async function fireChat() {
    const body = chatDraft.trim();
    if (!body || sendingChat) return;
    setSendingChat(true);
    setChatDraft('');
    try {
      const res = await sendMessage(token, id, body);
      setChat((c) => [...c, res.message]);
    } catch (e) {
      setChatDraft(body); // give the jab back rather than eating it
    } finally {
      setSendingChat(false);
    }
  }

  useEffect(() => {
    if (!result || celebrated.current) return;
    celebrated.current = true;
    refreshUser(); // the pot (or refund) just landed in the wallet
    Animated.spring(pop, { toValue: 1, friction: 5, tension: 80, useNativeDriver: true }).start();
    if (result.my_outcome === 'win') setConfetti(true);
    const type =
      result.my_outcome === 'win'
        ? NotifyType.Success
        : result.my_outcome === 'loss'
          ? NotifyType.Error
          : NotifyType.Warning;
    notify(type);
  }, [result, pop]);

  if (pending) {
    return (
      <Screen>
        <EmptyState
          icon="hourglass-outline"
          title="Results aren't in yet"
          subtitle="Your slips are sealed. The winner is declared once the games in the scoring window finish."
        />
      </Screen>
    );
  }

  if (error) {
    return (
      <Screen>
        <EmptyState icon="alert-circle-outline" title="Couldn't load the result" subtitle={error} />
      </Screen>
    );
  }

  if (!result) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  // The coin swing under the banner: net delta from the settle (payout − stake).
  function CoinLine() {
    if (!result.stake_coins) return null;
    const d = result.my_coin_delta || 0;
    const text =
      d > 0
        ? `◎ +${d.toLocaleString()} — pot of ${(result.pot_coins || 0).toLocaleString()} banked`
        : d < 0
          ? `◎ −${Math.abs(d).toLocaleString()} — stake surrendered`
          : '◎ Stakes returned';
    const color = d > 0 ? colors.gold : d < 0 ? colors.danger : colors.muted;
    return <Text style={[styles.coinLine, { color }]}>{text}</Text>;
  }

  function Team({ title, lineup, mine }) {
    const tint = mine ? colors.accent : colors.purpleText;
    return (
      <View style={[styles.five, { borderColor: withAlpha(mine ? colors.accent : colors.purple, 0.35) }]}>
        <View style={[styles.fiveHead, { backgroundColor: withAlpha(mine ? colors.accent : colors.purple, 0.08) }]}>
          <Text style={[styles.fiveTitle, { color: tint }]}>{title}</Text>
        </View>
        {lineup.players.map((p, i) => (
          <Pressable
            key={`${p.slot}-${p.player_id}`}
            onPress={() => navigation.navigate('PlayerProfile', { id: p.player_id, name: p.name, team: p.team, position: p.position })}
            style={({ pressed }) => [styles.playerRow, i > 0 && styles.playerTopBorder, pressed && { opacity: 0.7 }]}
          >
            <View style={styles.slotChip}>
              <Text style={styles.slotText}>{p.slot}</Text>
            </View>
            <PlayerAvatar uri={p.headshot_url} name={p.name} size={28} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.playerName} numberOfLines={1}>
                {p.name}
              </Text>
              <Text style={styles.statLine} numberOfLines={1}>
                {topStats(p.stat_line)}
              </Text>
            </View>
            <Text style={[styles.points, { color: tint }]}>{pn(p.points).toFixed(1)}</Text>
          </Pressable>
        ))}
      </View>
    );
  }

  // Group duel: ranked leaderboard instead of the VS scoreboard.
  const standings = result.standings || [];
  if (standings.length > 0) {
    const mine = standings.find((s) => s.is_me);
    const b = groupBanner(mine?.rank ?? standings.length, result.is_tie);
    const bannerColor = b.color === 'accent' ? colors.accent : b.color === 'danger' ? colors.danger : colors.text;

    const shareStandings = () =>
      Share.share({
        message: `I finished ${ordinal(mine?.rank ?? standings.length)} of ${standings.length} in our Heads Up group fantasy duel! 🏀⚾️`,
      }).catch(() => {});

    function StandRow({ s, last }) {
      const shown = useCountUp(pn(s.total));
      const champ = s.rank === 1;
      const name = s.is_me ? 'You' : s.username || 'Player';
      return (
        <Pressable
          disabled={s.is_me}
          onPress={() => navigation.navigate('UserProfile', { id: s.user_id, username: s.username })}
          style={({ pressed }) => [
            styles.standRow,
            champ && styles.standRowChamp,
            !last && styles.playerTopBorderB,
            pressed && { opacity: 0.7 },
          ]}
        >
          <Text style={styles.standRank}>{medal(s.rank)}</Text>
          <Avatar name={name} size={34} />
          <Text style={[styles.standName, s.is_me && { color: colors.accent }, champ && { color: colors.gold }]} numberOfLines={1}>
            {name}
            {champ ? ' 👑' : ''}
          </Text>
          <CondTitle size={champ ? 22 : 19} color={champ ? colors.gold : colors.text}>
            {shown.toFixed(1)}
          </CondTitle>
        </Pressable>
      );
    }

    return (
      <View style={{ flex: 1 }}>
        <Screen scroll padded={false}>
          <LinearGradient colors={[withAlpha(colors.accent, (scheme === 'dark' ? 1 : 0.5) * (mine?.rank === 1 ? 0.16 : 0.05)), 'transparent']} style={styles.glow}>
            <Animated.View style={{ alignItems: 'center', transform: [{ scale: pop }] }}>
              <Kicker tracking={3} color={colors.muted}>{`FINAL · ${standings.length}-WAY DUEL`}</Kicker>
              <DisplayTitle size={44} color={bannerColor} style={{ marginTop: 8 }}>
                {b.title}
              </DisplayTitle>
              <Text style={styles.resultSub}>{b.sub}</Text>
              <CoinLine />
            </Animated.View>
          </LinearGradient>

          <View style={{ paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl }}>
            <Card padded={false} style={{ overflow: 'hidden' }}>
              {standings.map((s, i) => (
                <StandRow key={s.user_id} s={s} last={i === standings.length - 1} />
              ))}
            </Card>

            {standings.map((s) => (
              <Team
                key={s.user_id}
                title={s.is_me ? 'YOUR SLIP' : `${(s.username || 'PLAYER').toUpperCase()}'S SLIP`}
                lineup={s}
                mine={s.is_me}
              />
            ))}

            <Pulse color={withAlpha(colors.accent, 0.3)} style={{ marginTop: spacing.xl }}>
              <Button title={rematching ? 'Sending…' : '⚡ Rematch the group'} onPress={doRematch} disabled={rematching} />
            </Pulse>
            <Button title="Share the receipt" icon="share-outline" variant="outline" onPress={shareStandings} style={{ marginTop: spacing.sm }} />

            <TrashTalk chat={chat} draft={chatDraft} setDraft={setChatDraft} onSend={fireChat} sending={sendingChat} />
          </View>
        </Screen>
        {confetti ? <ConfettiBurst /> : null}
      </View>
    );
  }

  const me = result.challenger.is_me ? result.challenger : result.opponent;
  const them = result.challenger.is_me ? result.opponent : result.challenger;
  const won = result.my_outcome === 'win';
  const tie = result.my_outcome === 'tie';
  const resultTitle = tie ? 'DEAD HEAT' : won ? 'YOU WIN.' : 'YOU LOST.';
  const resultColor = tie ? colors.text : won ? colors.accent : colors.danger;
  const resultSub = tie
    ? 'Nobody blinks. Run it back.'
    : won
      ? 'Bragging rights secured. Send the receipt.'
      : 'They got you this time. Instant rematch?';

  // Everyone from both slips, best night first.
  const perf = [
    ...(me.players || []).map((p) => ({ ...p, mine: true })),
    ...(them.players || []).map((p) => ({ ...p, mine: false })),
  ]
    .sort((a, b) => pn(b.points) - pn(a.points))
    .slice(0, 3);

  function shareResult() {
    const verb = won ? 'won' : result.my_outcome === 'loss' ? 'lost' : 'tied';
    Share.share({
      message: `I ${verb} my Heads Up fantasy duel vs ${opponentName} — ${pn(me.total).toFixed(1)} to ${pn(them.total).toFixed(1)}! 🏀⚾️`,
    }).catch(() => {});
  }

  function BigScore({ label, value, color, alignEnd }) {
    const shown = useCountUp(pn(value));
    return (
      <View style={{ alignItems: 'center' }}>
        <Kicker size={9.5} tracking={1} color={label === 'YOU' ? colors.accent : colors.purpleText}>
          {label}
        </Kicker>
        <Text style={[styles.finalScore, { color }, alignEnd && { textAlign: 'right' }]}>{shown.toFixed(1)}</Text>
      </View>
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <Screen scroll padded={false}>
        <LinearGradient colors={[withAlpha(colors.accent, (scheme === 'dark' ? 1 : 0.5) * (won ? 0.18 : 0.05)), 'transparent']} style={styles.glow}>
          <Animated.View style={{ alignItems: 'center', transform: [{ scale: pop }] }}>
            <Kicker tracking={3} color={colors.muted}>{`FINAL · DUEL VS ${opponentName.toUpperCase()}`}</Kicker>
            <DisplayTitle size={50} color={resultColor} style={{ marginTop: 8 }}>
              {resultTitle}
            </DisplayTitle>
            <View style={styles.finalRow}>
              <BigScore label="YOU" value={me.total} color={won || tie ? colors.accent : colors.text} />
              <GhostText size={19} color={colors.textFaint} strokeWidth={1}>
                VS
              </GhostText>
              <BigScore label={opponentName.toUpperCase()} value={them.total} color={!won && !tie ? colors.purpleText : colors.text} alignEnd />
            </View>
            <Text style={styles.resultSub}>{resultSub}</Text>
            <CoinLine />
          </Animated.View>
        </LinearGradient>

        <View style={{ paddingHorizontal: spacing.lg, paddingBottom: spacing.xxl }}>
          {/* Top performers across both slips */}
          <View style={styles.perfCard}>
            <View style={styles.perfHead}>
              <Text style={styles.perfHeadText}>TOP PERFORMERS</Text>
              <Text style={[styles.perfHeadText, { color: colors.placeholder }]}>FAN PTS</Text>
            </View>
            {perf.map((p, i) => (
              <View key={`${p.slot}-${p.player_id}-${p.mine}`} style={[styles.playerRow, i > 0 && styles.playerTopBorder]}>
                <CondTitle size={15} color={colors.placeholder} style={{ width: 16 }}>
                  {i + 1}
                </CondTitle>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={styles.playerName} numberOfLines={1}>
                    {p.name}
                  </Text>
                  <Text style={styles.statLine}>{p.mine ? 'Your slip' : `${opponentName}'s slip`}</Text>
                </View>
                <Text style={[styles.points, { color: p.mine ? colors.accent : colors.purpleText }]}>{pn(p.points).toFixed(1)}</Text>
              </View>
            ))}
          </View>

          <Team title="YOUR SLIP" lineup={me} mine />
          <Team title={`${opponentName.toUpperCase()}'S SLIP`} lineup={them} mine={false} />

          <Pulse color={withAlpha(colors.accent, 0.3)} style={{ marginTop: spacing.xl }}>
            <Button title={rematching ? 'Sending…' : '⚡ Instant rematch'} onPress={doRematch} disabled={rematching} />
          </Pulse>
          <Button title="Share the receipt" icon="share-outline" variant="outline" onPress={shareResult} style={{ marginTop: spacing.sm }} />

          <TrashTalk chat={chat} draft={chatDraft} setDraft={setChatDraft} onSend={fireChat} sending={sendingChat} />
        </View>
      </Screen>
      {confetti ? <ConfettiBurst /> : null}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    glow: { alignItems: 'center', paddingTop: spacing.xl, paddingBottom: spacing.lg, paddingHorizontal: spacing.lg },
    finalRow: { flexDirection: 'row', alignItems: 'center', gap: 16, marginTop: spacing.lg },
    finalScore: { fontFamily: fonts.hero, fontSize: 54, lineHeight: 56, paddingRight: 4 },
    resultSub: { color: colors.muted, fontSize: 11.5, fontFamily: fonts.bodySemi, marginTop: 10, textAlign: 'center' },
    coinLine: { fontSize: 14, fontFamily: fonts.condBold, letterSpacing: 0.5, marginTop: 8, textAlign: 'center' },
    perfCard: { borderRadius: 13, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.card, overflow: 'hidden' },
    perfHead: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      paddingVertical: 8,
      paddingHorizontal: 12,
      backgroundColor: colors.cardElevated,
    },
    perfHeadText: { fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.muted },
    five: { borderRadius: 13, borderWidth: 1, backgroundColor: colors.card, overflow: 'hidden', marginTop: spacing.md },
    fiveHead: { paddingVertical: 7, paddingHorizontal: 12 },
    fiveTitle: { fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1.5 },
    playerRow: { flexDirection: 'row', alignItems: 'center', gap: 9, paddingVertical: 9, paddingHorizontal: 12 },
    playerTopBorder: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    playerTopBorderB: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    slotChip: { backgroundColor: colors.cardElevated, borderRadius: 5, paddingVertical: 2, minWidth: 34, alignItems: 'center' },
    slotText: { color: colors.muted, fontSize: 8.5, fontFamily: fonts.bodyBlack },
    playerName: { color: colors.text, fontSize: 13, fontFamily: fonts.bodyBold },
    statLine: { color: colors.muted, fontSize: 10.5, fontFamily: fonts.body, marginTop: 1 },
    points: { fontSize: 19, fontFamily: fonts.hero, minWidth: 48, textAlign: 'right' },
    standRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: 10, paddingHorizontal: spacing.lg },
    standRowChamp: { backgroundColor: colors.warningSoft, paddingVertical: 14 },
    standRank: { fontSize: font.subtitle, width: 26, textAlign: 'center' },
    standName: { color: colors.text, fontSize: font.body, fontFamily: fonts.bodyBold, flex: 1 },
  });
```

## Shared component it uses: `ConfettiBurst.js`

```jsx
import { useEffect, useRef } from 'react';
import { Animated, Dimensions, Easing, StyleSheet, View } from 'react-native';

const COLORS = ['#C8FF2E', '#7C5CFF', '#22E5FF', '#FF4D8D', '#FFB021', '#F4F5F7'];
const COUNT = 42;

// A one-shot confetti rain for the winner moment. Pure Animated (no deps, runs
// in Expo Go): strips and dots fall from above the screen with drift and spin,
// fading out near the bottom. Mount it over the screen; it ignores touches.
export default function ConfettiBurst({ duration = 2800 }) {
  const pieces = useRef(
    Array.from({ length: COUNT }, (_, i) => ({
      progress: new Animated.Value(0),
      x: Math.random(),
      drift: (Math.random() - 0.5) * 140,
      size: 7 + Math.random() * 6,
      color: COLORS[i % COLORS.length],
      delay: Math.random() * 600,
      spin: (Math.random() < 0.5 ? -1 : 1) * (360 + Math.round(Math.random() * 360)),
      strip: Math.random() < 0.6,
    }))
  ).current;

  useEffect(() => {
    Animated.parallel(
      pieces.map((p) =>
        Animated.timing(p.progress, {
          toValue: 1,
          duration,
          delay: p.delay,
          easing: Easing.in(Easing.quad),
          useNativeDriver: true,
        })
      )
    ).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const { width, height } = Dimensions.get('window');

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      {pieces.map((p, i) => (
        <Animated.View
          key={i}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: p.strip ? p.size * 0.55 : p.size,
            height: p.strip ? p.size * 1.7 : p.size,
            borderRadius: p.strip ? 1.5 : p.size / 2,
            backgroundColor: p.color,
            opacity: p.progress.interpolate({ inputRange: [0, 0.75, 1], outputRange: [1, 1, 0] }),
            transform: [
              { translateX: p.progress.interpolate({ inputRange: [0, 1], outputRange: [p.x * width, p.x * width + p.drift] }) },
              { translateY: p.progress.interpolate({ inputRange: [0, 1], outputRange: [-30, height + 30] }) },
              { rotate: p.progress.interpolate({ inputRange: [0, 1], outputRange: ['0deg', `${p.spin}deg`] }) },
            ],
          }}
        />
      ))}
    </View>
  );
}
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
