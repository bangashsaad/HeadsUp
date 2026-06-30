import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import * as Haptics from 'expo-haptics';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listRequests, acceptRequest, deleteRequest } from '../api/social';
import { colors, spacing, font } from '../theme';
import { Screen, Avatar, Button, EmptyState, SkeletonList } from '../components/ui';

export default function RequestsScreen() {
  const { token } = useAuth();
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await listRequests(token);
      setRequests(res.requests);
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

  async function respond(request, action) {
    Haptics.notificationAsync(
      action === 'accept' ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Warning
    ).catch(() => {});

    // Remove from the list immediately for a snappy feel.
    setRequests((prev) => prev.filter((r) => r.id !== request.id));
    try {
      if (action === 'accept') {
        await acceptRequest(token, request.id);
      } else {
        await deleteRequest(token, request.id);
      }
    } catch (e) {
      setError(e.message);
      load(); // reload to restore correct state on error
    }
  }

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <SkeletonList count={4} />
        ) : (
          <FlatList
            data={requests}
            keyExtractor={(item) => String(item.id)}
            ItemSeparatorComponent={() => <View style={styles.sep} />}
            contentContainerStyle={requests.length === 0 && { flexGrow: 1, justifyContent: 'center' }}
            ListEmptyComponent={
              <EmptyState
                icon="mail-open-outline"
                title="No pending requests"
                subtitle="When someone wants to add you, it'll show up here."
              />
            }
            renderItem={({ item }) => (
              <View style={styles.row}>
                <Avatar name={item.user.username} size={44} />
                <Text style={styles.username}>{item.user.username}</Text>
                <View style={styles.buttons}>
                  <Button title="Accept" size="sm" full={false} icon="checkmark" onPress={() => respond(item, 'accept')} />
                  <Button title="Decline" size="sm" variant="outline" full={false} haptic={false} onPress={() => respond(item, 'decline')} />
                </View>
              </View>
            )}
          />
        )}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
  username: { color: colors.text, fontSize: font.subtitle, fontWeight: '600', marginLeft: spacing.md, flex: 1 },
  buttons: { flexDirection: 'row', gap: spacing.sm },
  error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.sm },
});
