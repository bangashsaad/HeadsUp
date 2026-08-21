import { useCallback, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listBlocked, unblockUser } from '../api/social';
import { useTheme, useThemedStyles, spacing, font, fonts } from '../theme';
import { Screen, Card, Avatar, EmptyState, SkeletonList } from '../components/ui';

// Everyone you've blocked, with the way back out. Unblocking does NOT restore
// the friendship — you can re-add each other if you both want to.
export default function BlockedScreen() {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [blocked, setBlocked] = useState(null);
  const [error, setError] = useState(null);
  const [busyId, setBusyId] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listBlocked(token);
      setBlocked(res.blocked || res.users || []);
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  async function unblock(u) {
    setBusyId(u.id);
    try {
      await unblockUser(token, u.id);
      setBlocked((cur) => (cur || []).filter((x) => x.id !== u.id));
    } catch (e) {
      Alert.alert("Couldn't unblock", e.message);
    } finally {
      setBusyId(null);
    }
  }

  if (error) {
    return (
      <Screen>
        <EmptyState icon="alert-circle-outline" title="Couldn't load the list" subtitle={error} />
      </Screen>
    );
  }

  if (blocked == null) {
    return (
      <Screen>
        <SkeletonList count={4} />
      </Screen>
    );
  }

  if (blocked.length === 0) {
    return (
      <Screen>
        <EmptyState
          icon="shield-checkmark-outline"
          title="Nobody's blocked"
          subtitle="Block someone from their rivalry page — it cancels shared duels and they can't reach you."
        />
      </Screen>
    );
  }

  return (
    <Screen scroll>
      <Card padded={false}>
        {blocked.map((u, i) => (
          <View key={u.id} style={[styles.row, i > 0 && styles.divider]}>
            <Avatar name={u.username} size={36} />
            <Text style={styles.name} numberOfLines={1}>
              {u.username}
            </Text>
            <Pressable
              onPress={() => unblock(u)}
              disabled={busyId === u.id}
              style={({ pressed }) => [styles.unblockBtn, (pressed || busyId === u.id) && { opacity: 0.6 }]}
            >
              <Text style={styles.unblockText}>{busyId === u.id ? '…' : 'UNBLOCK'}</Text>
            </Pressable>
          </View>
        ))}
      </Card>
      <Text style={styles.note}>Unblocking doesn't restore the friendship — you can re-add each other after.</Text>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    divider: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    name: { flex: 1, color: colors.text, fontSize: font.bodyLg, fontFamily: fonts.bodyBold },
    unblockBtn: { borderWidth: 1, borderColor: colors.border, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 7 },
    unblockText: { color: colors.muted, fontSize: 10.5, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
    note: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.lg, lineHeight: 18, fontFamily: fonts.body },
  });
