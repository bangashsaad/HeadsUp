import { useCallback, useState } from 'react';
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
          if (active) setSettled(true);
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
        <GhostText size={17} color={withAlpha('#3A4157', 0.9)} strokeWidth={1}>
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
