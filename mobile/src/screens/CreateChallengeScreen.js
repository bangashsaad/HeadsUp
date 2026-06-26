import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { listFriends } from '../api/social';
import { createChallenge } from '../api/duels';
import ChallengeForm from '../components/ChallengeForm';
import { colors } from '../theme';

export default function CreateChallengeScreen({ navigation }) {
  const { token } = useAuth();
  const [friends, setFriends] = useState([]);
  const [selected, setSelected] = useState(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    (async () => {
      try {
        const res = await listFriends(token);
        setFriends(res.friends);
      } catch (e) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    })();
  }, [token]);

  async function submit(terms) {
    if (!selected) {
      setError('Pick a friend to challenge first.');
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const res = await createChallenge(token, { opponent_id: selected, ...terms });
      navigation.replace('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: 40 }} />;
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ padding: 16 }}>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Text style={styles.label}>Who are you challenging?</Text>
      {friends.length === 0 ? (
        <Text style={styles.empty}>Add a friend first (Friends tab) to challenge them.</Text>
      ) : (
        friends.map((f) => {
          const active = selected === f.id;
          return (
            <TouchableOpacity
              key={f.id}
              style={[styles.friend, active && styles.friendActive]}
              onPress={() => setSelected(f.id)}
            >
              <Text style={[styles.friendName, active && { color: colors.bg }]}>
                {f.username}
              </Text>
              {active ? <Text style={styles.check}>✓</Text> : null}
            </TouchableOpacity>
          );
        })
      )}

      {friends.length > 0 ? (
        <ChallengeForm onSubmit={submit} submitLabel="Send Challenge" submitting={submitting} />
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  label: { color: colors.text, fontSize: 15, fontWeight: '700', marginBottom: 10 },
  friend: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    marginBottom: 8,
  },
  friendActive: { backgroundColor: colors.accent, borderColor: colors.accent },
  friendName: { color: colors.text, fontSize: 16, fontWeight: '600' },
  check: { color: colors.bg, fontSize: 18, fontWeight: '800' },
  empty: { color: colors.muted, fontSize: 15, lineHeight: 22 },
  error: { color: colors.danger, marginBottom: 12, textAlign: 'center' },
});
