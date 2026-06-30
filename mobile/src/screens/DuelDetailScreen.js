import { useCallback, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getDuel, respondToDuel } from '../api/duels';
import { formatDateTime } from '../utils/datetime';
import { colors, spacing, radius, font, statusTone } from '../theme';
import { Screen, Card, Avatar, Badge, Button, SectionHeader } from '../components/ui';

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
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  const isOpponentPending = duel.role === 'opponent' && duel.status === 'pending';
  const isChallengerPending = duel.role === 'challenger' && duel.status === 'pending';
  const scoring = Object.entries(duel.scoring_rules || {});

  return (
    <Screen scroll>
      <View style={styles.header}>
        <View style={styles.side}>
          <Avatar name="You" size={56} />
          <Text style={styles.sideName}>You</Text>
        </View>
        <Text style={styles.vs}>VS</Text>
        <View style={styles.side}>
          <Avatar name={duel.opponent.username} size={56} />
          <Text style={styles.sideName} numberOfLines={1}>
            {duel.opponent.username}
          </Text>
        </View>
      </View>

      <View style={styles.statusRow}>
        <Badge label={duel.status} tone={statusTone(duel.status)} dot />
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Card padded={false}>
        <Term label="Sport" value={SPORT_LABEL[duel.sport] || duel.sport} first />
        <Term label="Draft type" value={cap(duel.draft_type)} />
        <Term label="Lineup" value={`${cap((duel.lineup_template || '').split('_')[1] || '')} · ${duel.roster_size} slots`} />
        <Term label="Pick clock" value={clockLabel(duel.pick_clock_seconds)} />
        <Term label="Draft starts" value={formatDateTime(duel.draft_starts_at)} />
      </Card>

      <SectionHeader>Scoring chart</SectionHeader>
      <Card padded={false}>
        {scoring.map(([key, value], i) => (
          <Term key={key} label={prettyKey(key)} value={String(value)} first={i === 0} />
        ))}
      </Card>

      <View style={styles.actions}>
        {isOpponentPending ? (
          <>
            <Button title="Accept Challenge" icon="checkmark-circle" onPress={() => act('accept')} disabled={busy} />
            <View style={styles.twoUp}>
              <Button title="Counter" variant="outline" full={false} style={{ flex: 1 }} onPress={() => goCounter(navigation, duel)} disabled={busy} />
              <Button title="Decline" variant="danger" full={false} style={{ flex: 1 }} onPress={() => act('decline')} disabled={busy} />
            </View>
          </>
        ) : null}

        {isChallengerPending ? (
          <Button title="Cancel challenge" variant="danger" icon="close-circle" onPress={() => act('cancel')} disabled={busy} />
        ) : null}

        {duel.status === 'accepted' || duel.status === 'drafting' ? (
          <Button
            title={duel.status === 'drafting' ? 'Resume Live Draft' : 'Enter Draft Room'}
            icon="play"
            onPress={() => navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })}
          />
        ) : null}

        {duel.status === 'drafted' ? (
          <>
            <Button
              title="View Drafted Lineups"
              variant="outline"
              icon="list"
              onPress={() => navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Text style={styles.locked}>⏳ Lineups locked — the winner is declared once the games finish.</Text>
          </>
        ) : null}

        {duel.status === 'settled' ? (
          <Button
            title={
              duel.my_outcome === 'win'
                ? 'View Result — You won! 🏆'
                : duel.my_outcome === 'tie'
                  ? 'View Result — Tie 🤝'
                  : 'View Result'
            }
            icon="podium"
            onPress={() => navigation.navigate('Results', { id: duel.id, opponentName: duel.opponent.username })}
          />
        ) : null}
      </View>
    </Screen>
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

function Term({ label, value, first }) {
  return (
    <View style={[styles.term, !first && styles.termDivider]}>
      <Text style={styles.termLabel}>{label}</Text>
      <Text style={styles.termValue}>{value}</Text>
    </View>
  );
}

const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const prettyKey = (k) => k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

const styles = StyleSheet.create({
  loading: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md },
  side: { alignItems: 'center', flex: 1 },
  sideName: { color: colors.text, fontSize: font.body, fontWeight: '700', marginTop: spacing.sm, maxWidth: '90%' },
  vs: { color: colors.placeholder, fontSize: font.body, fontWeight: '800', letterSpacing: 1, paddingHorizontal: spacing.md },
  statusRow: { alignItems: 'center', marginBottom: spacing.lg },
  error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.md },
  term: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 13, paddingHorizontal: spacing.lg },
  termDivider: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
  termLabel: { color: colors.muted, fontSize: font.body },
  termValue: { color: colors.text, fontSize: font.body, fontWeight: '600' },
  actions: { marginTop: spacing.xl, gap: spacing.md },
  twoUp: { flexDirection: 'row', gap: spacing.md },
  locked: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.sm, lineHeight: 21 },
});
