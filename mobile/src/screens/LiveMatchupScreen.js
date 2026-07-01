import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getLiveResult } from '../api/duels';
import { ApiError } from '../api/client';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, Avatar, Badge } from '../components/ui';

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

  const me = live.challenger.is_me ? live.challenger : live.opponent;
  const them = live.challenger.is_me ? live.opponent : live.challenger;
  const meLeads = live.leader_id && me.user.id === live.leader_id;
  const themLead = live.leader_id && them.user.id === live.leader_id;
  const g = live.games || {};
  const gameLine =
    [g.final ? `${g.final} final` : null, g.live ? `${g.live} live` : null, g.upcoming ? `${g.upcoming} upcoming` : null]
      .filter(Boolean)
      .join(' · ') || 'No games in the scoring window yet';

  return (
    <Screen scroll>
      <Card style={styles.scoreCard}>
        <ScoreSide name="You" total={me.total} lead={meLeads} styles={styles} colors={colors} />
        <View style={styles.vsWrap}>
          <Text style={styles.vs}>VS</Text>
          {g.live > 0 ? <Badge label="LIVE" tone="danger" dot /> : null}
        </View>
        <ScoreSide name={opponentName} total={them.total} lead={themLead} styles={styles} colors={colors} />
      </Card>
      <Text style={styles.gamesLine}>{gameLine}</Text>

      <Lineup title="Your lineup" side={me} highlight={meLeads} styles={styles} colors={colors} />
      <Lineup title={`${opponentName}'s lineup`} side={them} highlight={themLead} styles={styles} colors={colors} />

      <Text style={styles.note}>Live scoring — the winner is declared automatically once the games are final.</Text>
    </Screen>
  );
}

function ScoreSide({ name, total, lead, styles, colors }) {
  return (
    <View style={styles.scoreSide}>
      <Avatar name={name} size={44} />
      <Text style={styles.scoreLabel} numberOfLines={1}>
        {name}
      </Text>
      <Text style={[styles.scoreValue, lead && { color: colors.accent }]}>{(total ?? 0).toFixed(1)}</Text>
      {lead ? <Text style={styles.leadTag}>LEADING</Text> : <Text style={styles.leadSpacer} />}
    </View>
  );
}

function Lineup({ title, side, highlight, styles, colors }) {
  return (
    <View style={styles.lineup}>
      <Text style={styles.lineupTitle}>{title}</Text>
      <Card padded={false} style={highlight && { borderColor: colors.accentBorder }}>
        {side.players.map((p, i) => (
          <View key={`${p.slot}-${p.player_id}`} style={[styles.playerRow, i < side.players.length - 1 && styles.playerDivider]}>
            <View style={styles.slotChip}>
              <Text style={styles.slotText}>{p.slot}</Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.playerName} numberOfLines={1}>
                {p.name || 'Player'}
              </Text>
              <Text style={styles.statLine}>{p.line ? p.line : 'Yet to play'}</Text>
            </View>
            <Text style={styles.points}>{p.points}</Text>
          </View>
        ))}
      </Card>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    scoreCard: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.xs },
    scoreSide: { flex: 1, alignItems: 'center' },
    scoreLabel: { color: colors.muted, fontSize: font.small, marginTop: spacing.sm, maxWidth: '90%' },
    scoreValue: { color: colors.text, fontSize: font.hero, fontWeight: '900', marginTop: 2 },
    leadTag: { color: colors.accent, fontSize: 10, fontWeight: '800', letterSpacing: 1, marginTop: 2 },
    leadSpacer: { fontSize: 10, marginTop: 2, height: 13 },
    vsWrap: { paddingHorizontal: spacing.sm, alignItems: 'center', gap: spacing.xs },
    vs: { color: colors.placeholder, fontSize: font.caption, fontWeight: '800', letterSpacing: 1 },
    gamesLine: { color: colors.muted, fontSize: font.small, textAlign: 'center', marginBottom: spacing.lg },
    lineup: { marginTop: spacing.md },
    lineupTitle: { color: colors.text, fontSize: font.bodyLg, fontWeight: '700', marginBottom: spacing.sm },
    playerRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingHorizontal: spacing.lg },
    playerDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    slotChip: { backgroundColor: colors.bgElevated, borderRadius: radius.sm, paddingHorizontal: 8, paddingVertical: 3, marginRight: spacing.md, minWidth: 46, alignItems: 'center' },
    slotText: { color: colors.muted, fontSize: 11, fontWeight: '800' },
    playerName: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    statLine: { color: colors.muted, fontSize: font.caption, marginTop: 2 },
    points: { color: colors.accent, fontSize: font.subtitle, fontWeight: '800', width: 52, textAlign: 'right' },
    note: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.lg, lineHeight: 18 },
  });
