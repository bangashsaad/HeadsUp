import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  SectionList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listDuels } from '../api/duels';
import { colors } from '../theme';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

// A friendly one-liner for the row: outcome for settled duels, else the status.
function rowMeta(d) {
  if (d.status === 'settled') {
    const o = d.my_outcome === 'win' ? 'You won 🏆' : d.my_outcome === 'tie' ? 'Tie' : 'You lost';
    return `${d.roster_size} players · ${o}`;
  }
  const label =
    d.status === 'drafting' ? 'drafting now' : d.status === 'drafted' ? 'awaiting results' : d.status;
  return `${d.roster_size} players · ${label}`;
}

export default function DuelsListScreen({ navigation }) {
  const { token } = useAuth();
  const [duels, setDuels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listDuels(token);
      setDuels(res.duels);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const sections = buildSections(duels);

  return (
    <View style={styles.container}>
      <TouchableOpacity
        style={styles.newBtn}
        onPress={() => navigation.navigate('CreateChallenge')}
      >
        <Text style={styles.newBtnText}>＋ New Challenge</Text>
      </TouchableOpacity>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading ? (
        <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: 30 }} />
      ) : (
        <SectionList
          sections={sections}
          keyExtractor={(item) => String(item.id)}
          stickySectionHeadersEnabled={false}
          ListEmptyComponent={
            <Text style={styles.empty}>
              No challenges yet.{'\n'}Tap “New Challenge” to duel a friend.
            </Text>
          }
          renderSectionHeader={({ section }) =>
            section.data.length ? <Text style={styles.sectionHeader}>{section.title}</Text> : null
          }
          renderItem={({ item }) => (
            <TouchableOpacity
              style={styles.row}
              onPress={() => navigation.navigate('DuelDetail', { id: item.id })}
            >
              <Text style={styles.emoji}>{SPORT_EMOJI[item.sport] || '🎯'}</Text>
              <View style={{ flex: 1 }}>
                <Text style={styles.vs}>vs {item.opponent.username}</Text>
                <Text style={styles.meta}>{rowMeta(item)}</Text>
              </View>
              <Text style={styles.chevron}>›</Text>
            </TouchableOpacity>
          )}
        />
      )}
    </View>
  );
}

// Group duels into meaningful buckets for the current user.
function buildSections(duels) {
  const needsResponse = [];
  const waiting = [];
  const active = [];
  const past = [];

  for (const d of duels) {
    if (d.status === 'pending' && d.role === 'opponent') needsResponse.push(d);
    else if (d.status === 'pending' && d.role === 'challenger') waiting.push(d);
    else if (['accepted', 'drafting', 'drafted'].includes(d.status)) active.push(d);
    else past.push(d);
  }

  return [
    { title: 'Needs your response', data: needsResponse },
    { title: 'Waiting on them', data: waiting },
    { title: 'In progress', data: active },
    { title: 'Past', data: past },
  ];
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: 16 },
  newBtn: {
    backgroundColor: colors.accent,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    marginBottom: 16,
  },
  newBtnText: { color: colors.bg, fontSize: 16, fontWeight: '700' },
  sectionHeader: {
    color: colors.muted,
    fontSize: 13,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginTop: 16,
    marginBottom: 6,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  emoji: { fontSize: 26, marginRight: 14 },
  vs: { color: colors.text, fontSize: 17, fontWeight: '600' },
  meta: { color: colors.muted, fontSize: 13, marginTop: 2 },
  chevron: { color: colors.muted, fontSize: 24 },
  empty: { color: colors.muted, textAlign: 'center', marginTop: 60, fontSize: 16, lineHeight: 24 },
  error: { color: colors.danger, textAlign: 'center', marginBottom: 10 },
});
