import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  RefreshControl,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listFriends, listRequests } from '../api/social';
import { colors } from '../theme';

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
      const [friendsRes, requestsRes] = await Promise.all([
        listFriends(token),
        listRequests(token),
      ]);
      setFriends(friendsRes.friends);
      setRequestCount(requestsRes.requests.length);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token]);

  // Reload every time this screen comes into focus (e.g. after accepting a request).
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
    <View style={styles.container}>
      <View style={styles.actions}>
        <TouchableOpacity style={styles.actionBtn} onPress={() => navigation.navigate('Search')}>
          <Text style={styles.actionText}>＋ Add friends</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.actionBtn} onPress={() => navigation.navigate('Requests')}>
          <Text style={styles.actionText}>Requests</Text>
          {requestCount > 0 ? (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{requestCount}</Text>
            </View>
          ) : null}
        </TouchableOpacity>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading ? (
        <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: 40 }} />
      ) : (
        <FlatList
          data={friends}
          keyExtractor={(item) => String(item.id)}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.muted} />
          }
          ListEmptyComponent={
            <Text style={styles.empty}>
              No friends yet.{'\n'}Tap “Add friends” to find your buddies.
            </Text>
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>
                  {item.username.charAt(0).toUpperCase()}
                </Text>
              </View>
              <Text style={styles.username}>{item.username}</Text>
            </View>
          )}
        />
      )}

      <TouchableOpacity style={styles.logout} onPress={signOut}>
        <Text style={styles.logoutText}>Log Out</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: 16 },
  actions: { flexDirection: 'row', gap: 12, marginBottom: 16 },
  actionBtn: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 14,
  },
  actionText: { color: colors.text, fontSize: 15, fontWeight: '600' },
  badge: {
    marginLeft: 8,
    backgroundColor: colors.accent,
    borderRadius: 10,
    minWidth: 20,
    paddingHorizontal: 6,
    paddingVertical: 1,
    alignItems: 'center',
  },
  badgeText: { color: colors.bg, fontSize: 12, fontWeight: '800' },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  avatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.card,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 14,
  },
  avatarText: { color: colors.accent, fontWeight: '800', fontSize: 16 },
  username: { color: colors.text, fontSize: 17 },
  empty: { color: colors.muted, textAlign: 'center', marginTop: 60, fontSize: 16, lineHeight: 24 },
  error: { color: colors.danger, textAlign: 'center', marginBottom: 10 },
  logout: {
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 8,
  },
  logoutText: { color: colors.danger, fontSize: 16, fontWeight: '600' },
});
