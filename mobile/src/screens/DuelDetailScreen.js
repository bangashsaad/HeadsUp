import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getDuel, respondToDuel } from '../api/duels';
import { formatDateTime } from '../utils/datetime';
import { colors } from '../theme';

const SPORT_LABEL = {
  nfl: '🏈 Football',
  nba: '🏀 Basketball',
  wnba: '🏀 WNBA',
  mlb: '⚾️ Baseball',
};

function clockLabel(secs) {
  if (!secs) return '—';
  if (secs < 3600) return `${secs}s per pick`;
  return `${secs / 3600}h per pick (async)`;
}

export default function DuelDetailScreen({ route, navigation }) {
  const { id } = route.params;
  const { token } = useAuth();
  const [duel, setDuel] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await getDuel(token, id);
      setDuel(res.duel);
    } catch (e) {
      setError(e.message);
    }
  }, [token, id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  async function act(action) {
    setBusy(true);
    setError(null);
    try {
      await respondToDuel(token, id, action);
      navigation.goBack();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  if (!duel) {
    return <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: 40 }} />;
  }

  const isOpponentPending = duel.role === 'opponent' && duel.status === 'pending';
  const isChallengerPending = duel.role === 'challenger' && duel.status === 'pending';
  const scoring = Object.entries(duel.scoring_rules || {});

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ padding: 16 }}>
      <Text style={styles.vs}>You vs {duel.opponent.username}</Text>
      <View style={[styles.statusPill, statusStyle(duel.status)]}>
        <Text style={styles.statusText}>{duel.status.toUpperCase()}</Text>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <View style={styles.card}>
        <Term label="Sport" value={SPORT_LABEL[duel.sport] || duel.sport} />
        <Term label="Draft type" value={cap(duel.draft_type)} />
        <Term label="Lineup" value={`${cap((duel.lineup_template || '').split('_')[1] || '')} · ${duel.roster_size} slots`} />
        <Term label="Pick clock" value={clockLabel(duel.pick_clock_seconds)} />
        <Term label="Draft starts" value={formatDateTime(duel.draft_starts_at)} />
      </View>

      <Text style={styles.section}>Scoring chart</Text>
      <View style={styles.card}>
        {scoring.map(([key, value]) => (
          <Term key={key} label={prettyKey(key)} value={String(value)} />
        ))}
      </View>

      {isOpponentPending ? (
        <>
          <TouchableOpacity style={styles.accept} onPress={() => act('accept')} disabled={busy}>
            <Text style={styles.acceptText}>Accept</Text>
          </TouchableOpacity>
          <View style={styles.twoUp}>
            <TouchableOpacity style={styles.counter} onPress={() => goCounter(navigation, duel)} disabled={busy}>
              <Text style={styles.counterText}>Counter</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.decline} onPress={() => act('decline')} disabled={busy}>
              <Text style={styles.declineText}>Decline</Text>
            </TouchableOpacity>
          </View>
        </>
      ) : null}

      {isChallengerPending ? (
        <TouchableOpacity style={styles.decline} onPress={() => act('cancel')} disabled={busy}>
          <Text style={styles.declineText}>Cancel challenge</Text>
        </TouchableOpacity>
      ) : null}

      {duel.status === 'accepted' || duel.status === 'drafting' ? (
        <TouchableOpacity
          style={styles.accept}
          onPress={() =>
            navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })
          }
        >
          <Text style={styles.acceptText}>
            {duel.status === 'drafting' ? 'Resume Live Draft' : 'Enter Draft Room'}
          </Text>
        </TouchableOpacity>
      ) : null}

      {duel.status === 'drafted' ? (
        <>
          <TouchableOpacity
            style={styles.counter}
            onPress={() =>
              navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })
            }
          >
            <Text style={styles.counterText}>View Drafted Lineups</Text>
          </TouchableOpacity>
          <Text style={styles.accepted}>⏳ Lineups locked — the winner is declared once the games finish.</Text>
        </>
      ) : null}

      {duel.status === 'settled' ? (
        <TouchableOpacity
          style={styles.accept}
          onPress={() =>
            navigation.navigate('Results', { id: duel.id, opponentName: duel.opponent.username })
          }
        >
          <Text style={styles.acceptText}>
            {duel.my_outcome === 'win'
              ? '🏆 View Result — You won!'
              : duel.my_outcome === 'tie'
                ? '🤝 View Result — Tie'
                : 'View Result'}
          </Text>
        </TouchableOpacity>
      ) : null}
    </ScrollView>
  );
}

function goCounter(navigation, duel) {
  navigation.navigate('Counter', {
    id: duel.id,
    initial: {
      sport: duel.sport,
      lineup_template: duel.lineup_template,
      pick_clock_seconds: duel.pick_clock_seconds,
    },
  });
}

function Term({ label, value }) {
  return (
    <View style={styles.term}>
      <Text style={styles.termLabel}>{label}</Text>
      <Text style={styles.termValue}>{value}</Text>
    </View>
  );
}

const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const prettyKey = (k) => k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

function statusStyle(status) {
  if (status === 'accepted' || status === 'drafted' || status === 'settled')
    return { backgroundColor: '#14532d' };
  if (status === 'drafting') return { backgroundColor: '#854d0e' };
  if (status === 'pending') return { backgroundColor: '#1e3a8a' };
  return { backgroundColor: colors.card };
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  vs: { color: colors.text, fontSize: 24, fontWeight: '800', textAlign: 'center' },
  statusPill: {
    alignSelf: 'center',
    borderRadius: 20,
    paddingHorizontal: 14,
    paddingVertical: 5,
    marginTop: 10,
    marginBottom: 8,
  },
  statusText: { color: colors.text, fontWeight: '800', fontSize: 12, letterSpacing: 1 },
  section: { color: colors.text, fontSize: 16, fontWeight: '700', marginTop: 22, marginBottom: 10 },
  card: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 14,
    paddingHorizontal: 16,
    marginTop: 8,
  },
  term: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  termLabel: { color: colors.muted, fontSize: 15 },
  termValue: { color: colors.text, fontSize: 15, fontWeight: '600' },
  accept: {
    backgroundColor: colors.accent,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    marginTop: 24,
  },
  acceptText: { color: colors.bg, fontSize: 16, fontWeight: '700' },
  twoUp: { flexDirection: 'row', gap: 12, marginTop: 12 },
  counter: {
    flex: 1,
    borderColor: colors.accent,
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  counterText: { color: colors.accent, fontSize: 15, fontWeight: '700' },
  decline: {
    flex: 1,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 12,
  },
  declineText: { color: colors.danger, fontSize: 15, fontWeight: '600' },
  accepted: { color: colors.accent, fontSize: 16, textAlign: 'center', marginTop: 24, lineHeight: 22 },
  error: { color: colors.danger, textAlign: 'center', marginTop: 12 },
});
