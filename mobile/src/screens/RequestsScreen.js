import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listRequests, acceptRequest, deleteRequest } from '../api/social';
import { colors } from '../theme';

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
    <View style={styles.container}>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading ? (
        <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: 40 }} />
      ) : (
        <FlatList
          data={requests}
          keyExtractor={(item) => String(item.id)}
          ListEmptyComponent={<Text style={styles.empty}>No pending requests.</Text>}
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Text style={styles.username}>{item.user.username}</Text>
              <View style={styles.buttons}>
                <TouchableOpacity
                  style={styles.accept}
                  onPress={() => respond(item, 'accept')}
                >
                  <Text style={styles.acceptText}>Accept</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={styles.decline}
                  onPress={() => respond(item, 'decline')}
                >
                  <Text style={styles.declineText}>Decline</Text>
                </TouchableOpacity>
              </View>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: 16 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 14,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  username: { color: colors.text, fontSize: 17, flex: 1 },
  buttons: { flexDirection: 'row', gap: 10 },
  accept: { backgroundColor: colors.accent, borderRadius: 10, paddingHorizontal: 16, paddingVertical: 8 },
  acceptText: { color: colors.bg, fontWeight: '700' },
  decline: {
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  declineText: { color: colors.muted, fontWeight: '600' },
  empty: { color: colors.muted, textAlign: 'center', marginTop: 60, fontSize: 16 },
});
