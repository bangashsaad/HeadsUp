import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useAuth } from '../auth/AuthContext';
import { listFriends } from '../api/social';
import { createChallenge } from '../api/duels';
import ChallengeForm from '../components/ChallengeForm';
import { colors, spacing, radius, font } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList, SectionHeader } from '../components/ui';

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
    return (
      <Screen>
        <SkeletonList count={5} />
      </Screen>
    );
  }

  return (
    <Screen scroll>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      <SectionHeader style={{ marginTop: 0 }}>Who are you challenging?</SectionHeader>

      {friends.length === 0 ? (
        <EmptyState
          icon="people-outline"
          title="No friends yet"
          subtitle="Add a friend from the Friends tab before you can challenge them."
        />
      ) : (
        friends.map((f) => {
          const active = selected === f.id;
          return (
            <Pressable
              key={f.id}
              onPress={() => {
                Haptics.selectionAsync().catch(() => {});
                setSelected(f.id);
              }}
              style={({ pressed }) => [styles.friend, active && styles.friendActive, pressed && { opacity: 0.9 }]}
            >
              <Avatar name={f.username} size={40} />
              <Text style={styles.friendName}>{f.username}</Text>
              <Ionicons
                name={active ? 'checkmark-circle' : 'ellipse-outline'}
                size={22}
                color={active ? colors.accent : colors.placeholder}
              />
            </Pressable>
          );
        })
      )}

      {friends.length > 0 ? <ChallengeForm onSubmit={submit} submitLabel="Send Challenge" submitting={submitting} /> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  error: { color: colors.danger, marginBottom: spacing.md, textAlign: 'center' },
  friend: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    marginBottom: spacing.sm,
  },
  friendActive: { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder },
  friendName: { color: colors.text, fontSize: font.bodyLg, fontWeight: '600', flex: 1, marginLeft: spacing.md },
});
