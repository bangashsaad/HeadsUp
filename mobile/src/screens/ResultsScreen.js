import { useCallback, useState } from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getResult } from '../api/duels';
import { ApiError } from '../api/client';
import { colors } from '../theme';

export default function ResultsScreen({ route }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token } = useAuth();
  const [result, setResult] = useState(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      (async () => {
        // Reset transient flags each fetch so a later settle replaces an earlier
        // "results aren't in yet" / error state on re-focus.
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

  if (pending) {
    return (
      <View style={styles.center}>
        <Text style={styles.pendingTitle}>Results aren’t in yet</Text>
        <Text style={styles.dim}>
          Your lineups are locked. The winner is declared once the games in the scoring window
          finish.
        </Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={styles.dim}>{error}</Text>
      </View>
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
  const banner =
    result.my_outcome === 'win'
      ? '🏆 You win!'
      : result.my_outcome === 'tie'
        ? '🤝 Tie'
        : '😔 You lost';

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ padding: 16 }}>
      <Text style={[styles.banner, bannerStyle(result.my_outcome)]}>{banner}</Text>

      <View style={styles.scoreRow}>
        <Score label="You" value={me.total} win={result.my_outcome === 'win'} />
        <Text style={styles.vs}>vs</Text>
        <Score label={opponentName} value={them.total} win={result.my_outcome === 'loss'} />
      </View>

      <Team title="Your lineup" lineup={me} />
      <Team title={`${opponentName}'s lineup`} lineup={them} />
    </ScrollView>
  );
}

function Score({ label, value, win }) {
  return (
    <View style={styles.score}>
      <Text style={styles.scoreLabel}>{label}</Text>
      <Text style={[styles.scoreValue, win && styles.scoreWin]}>{value}</Text>
    </View>
  );
}

function Team({ title, lineup }) {
  return (
    <View style={styles.team}>
      <Text style={styles.teamTitle}>{title}</Text>
      <View style={styles.card}>
        {lineup.players.map((p) => (
          <View key={`${p.slot}-${p.player_id}`} style={styles.playerRow}>
            <Text style={styles.slot}>{p.slot}</Text>
            <View style={{ flex: 1 }}>
              <Text style={styles.playerName}>{p.name}</Text>
              <Text style={styles.statLine}>{topStats(p.stat_line)}</Text>
            </View>
            <Text style={styles.points}>{p.points}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

// Show the player's non-zero stats compactly, e.g. "28 point · 9 rebound".
function topStats(statLine) {
  const entries = Object.entries(statLine || {}).filter(([, v]) => v);
  if (entries.length === 0) return 'no stats';
  return entries
    .slice(0, 4)
    .map(([k, v]) => `${v} ${k.replace(/_/g, ' ')}`)
    .join(' · ');
}

const bannerStyle = (o) =>
  o === 'win' ? { color: colors.accent } : o === 'loss' ? { color: colors.danger } : { color: colors.text };

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center', padding: 24 },
  dim: { color: colors.muted, marginTop: 12, textAlign: 'center', lineHeight: 20 },
  pendingTitle: { color: colors.text, fontSize: 22, fontWeight: '800', textAlign: 'center' },
  banner: { fontSize: 28, fontWeight: '900', textAlign: 'center', marginVertical: 12 },
  scoreRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginBottom: 20 },
  score: { alignItems: 'center', flex: 1 },
  scoreLabel: { color: colors.muted, fontSize: 14 },
  scoreValue: { color: colors.text, fontSize: 34, fontWeight: '800', marginTop: 4 },
  scoreWin: { color: colors.accent },
  vs: { color: colors.muted, fontSize: 14, marginHorizontal: 8 },
  team: { marginTop: 18 },
  teamTitle: { color: colors.text, fontSize: 16, fontWeight: '700', marginBottom: 8 },
  card: { backgroundColor: colors.card, borderColor: colors.border, borderWidth: 1, borderRadius: 12, paddingHorizontal: 14 },
  playerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 11,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  slot: { color: colors.muted, fontSize: 12, fontWeight: '700', width: 48 },
  playerName: { color: colors.text, fontSize: 15, fontWeight: '600' },
  statLine: { color: colors.muted, fontSize: 12, marginTop: 2 },
  points: { color: colors.accent, fontSize: 17, fontWeight: '800', width: 52, textAlign: 'right' },
});
