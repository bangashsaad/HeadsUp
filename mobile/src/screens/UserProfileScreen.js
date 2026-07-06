import { useCallback, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getUserProfile, sendFriendRequest, acceptRequest } from '../api/social';
import { notify, NotifyType } from '../haptics';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Card, Avatar, Badge, Button, EmptyState } from '../components/ui';

// Another player's profile, reachable by tapping them anywhere in a game
// (challenge seats, live standings, results). Shows their record, your
// head-to-head, and the friend action — how you add someone you just met
// in a group duel.
export default function UserProfileScreen({ route }) {
  const { id, username: usernameParam } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [profile, setProfile] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      (async () => {
        try {
          const res = await getUserProfile(token, id);
          if (active) setProfile(res.profile);
        } catch (e) {
          if (active) setError(e.message);
        }
      })();
      return () => {
        active = false;
      };
    }, [token, id])
  );

  async function addFriend() {
    setBusy(true);
    setError(null);
    try {
      await sendFriendRequest(token, id);
      notify(NotifyType.Success);
      setProfile((p) => ({ ...p, relationship: 'request_sent' }));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function acceptFriend() {
    setBusy(true);
    setError(null);
    try {
      await acceptRequest(token, profile.friendship_id);
      notify(NotifyType.Success);
      setProfile((p) => ({ ...p, relationship: 'friends' }));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  if (error && !profile) {
    return (
      <Screen>
        <EmptyState icon="alert-circle-outline" title="Couldn't load this profile" subtitle={error} />
      </Screen>
    );
  }

  if (!profile) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  const name = profile.user.username || usernameParam;
  const r = profile.record;
  const vs = profile.vs_you;

  return (
    <Screen scroll>
      <View style={styles.head}>
        <Avatar name={name} size={72} />
        <Text style={styles.username}>{name}</Text>
        {profile.relationship === 'friends' ? <Badge label="Friends" tone="accent" /> : null}
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {profile.relationship === 'none' ? (
        <Button title={busy ? 'Sending…' : 'Add Friend'} icon="person-add" onPress={addFriend} disabled={busy} />
      ) : null}
      {profile.relationship === 'request_sent' ? (
        <Button title="Friend request sent ⏳" variant="outline" disabled onPress={() => {}} />
      ) : null}
      {profile.relationship === 'request_received' ? (
        <Button
          title={busy ? 'Accepting…' : 'Accept Friend Request'}
          icon="checkmark-circle"
          onPress={acceptFriend}
          disabled={busy}
        />
      ) : null}

      <Card style={styles.recordCard}>
        <Text style={styles.cardHead}>RECORD</Text>
        <View style={styles.recordRow}>
          <Stat label="W" value={r.wins} color={colors.accent} styles={styles} />
          <Stat label="L" value={r.losses} color={colors.danger} styles={styles} />
          <Stat label="T" value={r.ties} color={colors.muted} styles={styles} />
          <Stat label="Played" value={r.played} color={colors.text} styles={styles} />
        </View>
        {r.streak?.count > 0 ? (
          <Text style={styles.streak}>
            {r.streak.type === 'win' ? '🔥' : ''} {r.streak.count}-{r.streak.type} streak
          </Text>
        ) : null}
      </Card>

      {vs ? (
        <Card style={styles.recordCard}>
          <Text style={styles.cardHead}>YOU vs {name.toUpperCase()}</Text>
          <Text style={styles.vsLine}>
            <Text style={{ color: colors.accent, fontWeight: '800' }}>{vs.wins}</Text> – {vs.losses}
            {vs.ties > 0 ? ` – ${vs.ties}` : ''} <Text style={styles.vsMuted}>({vs.played} duels)</Text>
          </Text>
        </Card>
      ) : (
        <Text style={styles.note}>You haven't finished a 1v1 against {name} yet.</Text>
      )}
    </Screen>
  );
}

function Stat({ label, value, color, styles }) {
  return (
    <View style={styles.stat}>
      <Text style={[styles.statValue, { color }]}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    head: { alignItems: 'center', gap: spacing.sm, marginBottom: spacing.lg },
    username: { color: colors.text, fontSize: 26, fontFamily: fonts.hero, paddingRight: 4 },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.md },
    recordCard: { marginTop: spacing.lg },
    cardHead: { color: colors.muted, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 2, textAlign: 'center', marginBottom: spacing.md, textTransform: 'uppercase' },
    recordRow: { flexDirection: 'row', justifyContent: 'space-around' },
    stat: { alignItems: 'center' },
    statValue: { fontSize: 24, fontFamily: fonts.hero },
    statLabel: { color: colors.muted, fontSize: font.caption, fontWeight: '700', marginTop: 2 },
    streak: { color: colors.muted, fontSize: font.small, textAlign: 'center', marginTop: spacing.md },
    vsLine: { color: colors.text, fontSize: 24, fontFamily: fonts.hero, textAlign: 'center', paddingRight: 4 },
    vsMuted: { color: colors.muted, fontSize: font.small, fontWeight: '400' },
    note: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.lg },
  });
