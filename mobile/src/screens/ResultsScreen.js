import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getResult, rematch } from '../api/duels';
import { ApiError } from '../api/client';
import ConfettiBurst from '../components/ConfettiBurst';
import { notify, NotifyType } from '../haptics';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { Screen, Card, Avatar, Button, EmptyState, GhostText, Kicker, DisplayTitle, CondTitle, Pulse } from '../components/ui';

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
  const { token } = useAuth();
  const { colors, scheme } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [result, setResult] = useState(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(null);
  const celebrated = useRef(false);
  const pop = useRef(new Animated.Value(0.85)).current;
  const [rematching, setRematching] = useState(false);
  const [confetti, setConfetti] = useState(false);

  async function doRematch() {
    setRematching(true);
    try {
      const res = await rematch(token, id);
      navigation.navigate('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setRematching(false);
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
      return () => {
        active = false;
      };
    }, [token, id])
  );

  useEffect(() => {
    if (!result || celebrated.current) return;
    celebrated.current = true;
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
  if (standings.length > 2) {
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
