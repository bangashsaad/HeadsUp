import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import * as Haptics from 'expo-haptics';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getResult } from '../api/duels';
import { ApiError } from '../api/client';
import { colors, spacing, radius, font, tones } from '../theme';
import { Screen, Card, Avatar, EmptyState } from '../components/ui';

const OUTCOME = {
  win: { tone: 'accent', icon: '🏆', title: 'You win!' },
  tie: { tone: 'neutral', icon: '🤝', title: "It's a tie" },
  loss: { tone: 'danger', icon: '😤', title: 'You lost' },
};

export default function ResultsScreen({ route }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token } = useAuth();
  const [result, setResult] = useState(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(null);
  const celebrated = useRef(false);

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

  // A little haptic fanfare the first time a final result lands.
  useEffect(() => {
    if (!result || celebrated.current) return;
    celebrated.current = true;
    const type =
      result.my_outcome === 'win'
        ? Haptics.NotificationFeedbackType.Success
        : result.my_outcome === 'loss'
          ? Haptics.NotificationFeedbackType.Error
          : Haptics.NotificationFeedbackType.Warning;
    Haptics.notificationAsync(type).catch(() => {});
  }, [result]);

  if (pending) {
    return (
      <Screen>
        <EmptyState
          icon="hourglass-outline"
          title="Results aren't in yet"
          subtitle="Your lineups are locked. The winner is declared once the games in the scoring window finish."
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

  const me = result.challenger.is_me ? result.challenger : result.opponent;
  const them = result.challenger.is_me ? result.opponent : result.challenger;
  const o = OUTCOME[result.my_outcome] || OUTCOME.tie;
  const tone = tones[o.tone];

  return (
    <Screen scroll>
      <View style={[styles.banner, { backgroundColor: tone.bg, borderColor: tone.border }]}>
        <Text style={styles.bannerEmoji}>{o.icon}</Text>
        <Text style={[styles.bannerTitle, { color: tone.text }]}>{o.title}</Text>
      </View>

      <Card style={styles.scoreCard}>
        <ScoreSide name="You" value={me.total} win={result.my_outcome === 'win'} />
        <View style={styles.vsWrap}>
          <Text style={styles.vs}>VS</Text>
        </View>
        <ScoreSide name={opponentName} value={them.total} win={result.my_outcome === 'loss'} />
      </Card>

      <Team title="Your lineup" lineup={me} highlight={result.my_outcome === 'win'} />
      <Team title={`${opponentName}'s lineup`} lineup={them} highlight={result.my_outcome === 'loss'} />
    </Screen>
  );
}

function ScoreSide({ name, value, win }) {
  return (
    <View style={styles.scoreSide}>
      <Avatar name={name} size={48} />
      <Text style={styles.scoreLabel} numberOfLines={1}>
        {name}
      </Text>
      <Text style={[styles.scoreValue, win && { color: colors.accent }]}>{value}</Text>
      {win ? <Text style={styles.winnerTag}>WINNER</Text> : <Text style={styles.spacerTag} />}
    </View>
  );
}

function Team({ title, lineup, highlight }) {
  return (
    <View style={styles.team}>
      <Text style={styles.teamTitle}>{title}</Text>
      <Card padded={false} style={highlight && { borderColor: colors.accentBorder }}>
        {lineup.players.map((p, i) => (
          <View
            key={`${p.slot}-${p.player_id}`}
            style={[styles.playerRow, i < lineup.players.length - 1 && styles.playerDivider]}
          >
            <View style={styles.slotChip}>
              <Text style={styles.slotText}>{p.slot}</Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.playerName}>{p.name}</Text>
              <Text style={styles.statLine}>{topStats(p.stat_line)}</Text>
            </View>
            <Text style={styles.points}>{p.points}</Text>
          </View>
        ))}
      </Card>
    </View>
  );
}

function topStats(statLine) {
  const entries = Object.entries(statLine || {}).filter(([, v]) => v);
  if (entries.length === 0) return 'did not play';
  return entries
    .slice(0, 4)
    .map(([k, v]) => `${v} ${k.replace(/_/g, ' ')}`)
    .join(' · ');
}

const styles = StyleSheet.create({
  center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
  banner: {
    borderRadius: radius.lg,
    borderWidth: 1,
    alignItems: 'center',
    paddingVertical: spacing.xl,
    marginBottom: spacing.lg,
  },
  bannerEmoji: { fontSize: 44 },
  bannerTitle: { fontSize: font.titleLg, fontWeight: '900', marginTop: spacing.sm },
  scoreCard: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg },
  scoreSide: { flex: 1, alignItems: 'center' },
  scoreLabel: { color: colors.muted, fontSize: font.small, marginTop: spacing.sm, maxWidth: '90%' },
  scoreValue: { color: colors.text, fontSize: font.hero, fontWeight: '900', marginTop: 2 },
  winnerTag: { color: colors.accent, fontSize: 10, fontWeight: '800', letterSpacing: 1, marginTop: 2 },
  spacerTag: { fontSize: 10, marginTop: 2, height: 13 },
  vsWrap: { paddingHorizontal: spacing.sm },
  vs: { color: colors.placeholder, fontSize: font.caption, fontWeight: '800', letterSpacing: 1 },
  team: { marginTop: spacing.lg },
  teamTitle: { color: colors.text, fontSize: font.bodyLg, fontWeight: '700', marginBottom: spacing.sm },
  playerRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingHorizontal: spacing.lg },
  playerDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
  slotChip: {
    backgroundColor: colors.bgElevated,
    borderRadius: radius.sm,
    paddingHorizontal: 8,
    paddingVertical: 3,
    marginRight: spacing.md,
    minWidth: 46,
    alignItems: 'center',
  },
  slotText: { color: colors.muted, fontSize: 11, fontWeight: '800' },
  playerName: { color: colors.text, fontSize: font.body, fontWeight: '600' },
  statLine: { color: colors.muted, fontSize: font.caption, marginTop: 2 },
  points: { color: colors.accent, fontSize: font.subtitle, fontWeight: '800', width: 52, textAlign: 'right' },
});
