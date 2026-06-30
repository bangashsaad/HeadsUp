import { useCallback, useState } from 'react';
import { FlatList, RefreshControl, StyleSheet, Text, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listFriends, listRequests } from '../api/social';
import { colors, spacing, radius, font } from '../theme';
import { Screen, Avatar, Button, EmptyState, SkeletonList } from '../components/ui';

function ActionTile({ icon, label, onPress, count = 0 }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.tile, pressed && { opacity: 0.85, transform: [{ scale: 0.99 }] }]}>
      <Ionicons name={icon} size={20} color={colors.accent} />
      <Text style={styles.tileText}>{label}</Text>
      {count > 0 ? (
        <View style={styles.countBadge}>
          <Text style={styles.countText}>{count}</Text>
        </View>
      ) : null}
    </Pressable>
  );
}

export default function FriendsScreen({ navigation }) {
  const { token, signOut } = useAuth();
  const [friends, setFriends] = useState([]);
  const [requestCount, setRequestCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [friendsRes, requestsRes] = await Promise.all([listFriends(token), listRequests(token)]);
      setFriends(friendsRes.friends);
      setRequestCount(requestsRes.requests.length);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function onRefresh() {
    setRefreshing(true);
    load();
  }

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <View style={styles.actions}>
          <ActionTile icon="person-add" label="Add friends" onPress={() => navigation.navigate('Search')} />
          <ActionTile icon="mail" label="Requests" count={requestCount} onPress={() => navigation.navigate('Requests')} />
        </View>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <SkeletonList count={6} />
        ) : (
          <FlatList
            data={friends}
            keyExtractor={(item) => String(item.id)}
            refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.muted} />}
            ItemSeparatorComponent={() => <View style={styles.sep} />}
            contentContainerStyle={friends.length === 0 && { flexGrow: 1, justifyContent: 'center' }}
            ListEmptyComponent={
              <EmptyState
                icon="people-outline"
                title="No friends yet"
                subtitle="Add your buddies to start challenging them head-to-head."
                action={<Button title="Add friends" icon="person-add" onPress={() => navigation.navigate('Search')} />}
              />
            }
            renderItem={({ item }) => (
              <View style={styles.row}>
                <Avatar name={item.username} size={44} />
                <Text style={styles.username}>{item.username}</Text>
              </View>
            )}
          />
        )}
      </View>

      <View style={styles.footer}>
        <Button title="Log Out" variant="danger" icon="log-out-outline" onPress={signOut} />
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
  actions: { flexDirection: 'row', gap: spacing.md, marginBottom: spacing.md },
  tile: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: radius.md,
    paddingVertical: 14,
  },
  tileText: { color: colors.text, fontSize: font.body, fontWeight: '700', marginLeft: 8 },
  countBadge: {
    marginLeft: 8,
    backgroundColor: colors.accent,
    borderRadius: 10,
    minWidth: 20,
    paddingHorizontal: 6,
    paddingVertical: 1,
    alignItems: 'center',
  },
  countText: { color: colors.bg, fontSize: font.caption, fontWeight: '800' },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
  username: { color: colors.text, fontSize: font.subtitle, fontWeight: '600', marginLeft: spacing.md },
  error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.sm },
  footer: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
});
