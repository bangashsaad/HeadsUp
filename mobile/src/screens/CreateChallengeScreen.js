import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { listFriends } from '../api/social';
import { createChallenge } from '../api/duels';
import { selection } from '../haptics';
import ChallengeForm from '../components/ChallengeForm';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList, SectionHeader } from '../components/ui';

const MAX_INVITEES = 3;

export default function CreateChallengeScreen({ navigation }) {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [friends, setFriends] = useState([]);
  const [selected, setSelected] = useState([]);
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

  function toggle(id) {
    selection();
    setError(null);
    setSelected((cur) => {
      if (cur.includes(id)) return cur.filter((x) => x !== id);
      if (cur.length >= MAX_INVITEES) {
        setError(`Max ${MAX_INVITEES + 1} players — deselect someone first.`);
        return cur;
      }
      return [...cur, id];
    });
  }

  async function submit(terms) {
    if (selected.length === 0) {
      setError('Pick at least one friend to challenge.');
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const who = selected.length === 1 ? { opponent_id: selected[0] } : { opponent_ids: selected };
      const res = await createChallenge(token, { ...who, ...terms });
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

  const group = selected.length > 1;

  return (
    <Screen scroll>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      <SectionHeader style={{ marginTop: 0 }}>Who are you challenging?</SectionHeader>
      <Text style={styles.hint}>Pick one friend for a duel — or up to {MAX_INVITEES} for a group match.</Text>

      {friends.length === 0 ? (
        <EmptyState icon="people-outline" title="No friends yet" subtitle="Add a friend from the Friends tab before you can challenge them." />
      ) : (
        friends.map((f) => {
          const active = selected.includes(f.id);
          return (
            <Pressable
              key={f.id}
              onPress={() => toggle(f.id)}
              style={({ pressed }) => [styles.friend, active && styles.friendActive, pressed && { opacity: 0.9 }]}
            >
              <Avatar name={f.username} size={40} />
              <Text style={styles.friendName}>{f.username}</Text>
              <Ionicons name={active ? 'checkmark-circle' : 'ellipse-outline'} size={22} color={active ? colors.accent : colors.placeholder} />
            </Pressable>
          );
        })
      )}

      {group ? (
        <Text style={styles.groupNote}>
          👥 Group match — {selected.length + 1} players. Everyone drafts their own team; best total wins. Friends accept
          their own invite, and you can start once at least 2 are in.
        </Text>
      ) : null}

      {friends.length > 0 ? (
        <ChallengeForm onSubmit={submit} submitLabel={group ? 'Send Group Invites' : 'Send Challenge'} submitting={submitting} />
      ) : null}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    error: { color: colors.danger, marginBottom: spacing.md, textAlign: 'center' },
    hint: { color: colors.muted, fontSize: font.small, marginBottom: spacing.md },
    groupNote: {
      color: colors.accent,
      fontSize: font.small,
      lineHeight: 19,
      backgroundColor: colors.accentSoft,
      borderColor: colors.accentBorder,
      borderWidth: 1,
      borderRadius: radius.md,
      padding: spacing.md,
      marginTop: spacing.sm,
    },
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
