import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getLiveResult } from '../api/duels';
import { ApiError } from '../api/client';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { Screen, Card, Avatar, Badge, Button, GhostText, Kicker, CondTitle } from '../components/ui';

const pts = (v) => (Number(v) || 0).toFixed(1);

export default function LiveMatchupScreen({ route, navigation }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [live, setLive] = useState(null);
  const [error, setError] = useState(null);
  const timer = useRef(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
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
              <CondTitle size={19} color={i === 0 ? colors.accent : colors.text}>
                {pts(s.total)}
              </CondTitle>
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
              <Text style={[styles.scoreBig, { color: myT >= opT ? colors.accent : colors.text }]}>{myT.toFixed(1)}</Text>
            </View>
            <GhostText size={17} color={colors.textFaint} strokeWidth={1}>
              VS
            </GhostText>
            <View style={{ alignItems: 'flex-end' }}>
              <Kicker size={10} tracking={1} color={colors.purpleText}>
                {opponentName}
              </Kicker>
              <Text style={[styles.scoreBig, { color: opT > myT ? colors.purpleText : colors.text }]}>{opT.toFixed(1)}</Text>
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
      {players.map((p, i) => (
        <View key={`${p.slot}-${p.player_id}`} style={[styles.playerRow, i > 0 && styles.playerTopBorder]}>
          <View style={styles.slotChip}>
            <Text style={styles.slotText}>{p.slot}</Text>
          </View>
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.playerName} numberOfLines={1}>
              {p.name || 'Player'}
            </Text>
            <Text style={styles.statLine} numberOfLines={1}>
              {p.line ? p.line : 'Yet to check in'}
            </Text>
          </View>
          <Text style={[styles.points, { color: tint }]}>{pts(p.points)}</Text>
        </View>
      ))}
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
