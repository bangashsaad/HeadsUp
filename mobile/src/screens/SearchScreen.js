import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { searchUsers, sendFriendRequest } from '../api/social';
import { colors } from '../theme';

export default function SearchScreen() {
  const { token } = useAuth();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // Debounced live search: wait 300ms after the last keystroke, then search.
  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < 2) {
      setResults([]);
      return;
    }

    let cancelled = false;
    setLoading(true);
    const timer = setTimeout(async () => {
      try {
        const res = await searchUsers(token, trimmed);
        if (!cancelled) setResults(res.users);
      } catch (e) {
        if (!cancelled) setError(e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 300);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query, token]);

  async function add(user) {
    // Optimistically flip the button to "Requested".
    setResults((prev) =>
      prev.map((u) => (u.id === user.id ? { ...u, relationship: 'request_sent' } : u))
    );
    try {
      await sendFriendRequest(token, user.id);
    } catch (e) {
      setError(e.message);
      // Roll back on failure.
      setResults((prev) =>
        prev.map((u) => (u.id === user.id ? { ...u, relationship: 'none' } : u))
      );
    }
  }

  function renderButton(user) {
    switch (user.relationship) {
      case 'friends':
        return <Text style={styles.tag}>✓ Friends</Text>;
      case 'request_sent':
        return <Text style={styles.tag}>Requested</Text>;
      case 'request_received':
        return <Text style={styles.tag}>Wants to add you</Text>;
      default:
        return (
          <TouchableOpacity style={styles.addBtn} onPress={() => add(user)}>
            <Text style={styles.addText}>Add</Text>
          </TouchableOpacity>
        );
    }
  }

  return (
    <View style={styles.container}>
      <TextInput
        style={styles.input}
        placeholder="Search by username"
        placeholderTextColor={colors.placeholder}
        autoCapitalize="none"
        autoCorrect={false}
        autoFocus
        value={query}
        onChangeText={setQuery}
      />

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <FlatList
        data={results}
        keyExtractor={(item) => String(item.id)}
        keyboardShouldPersistTaps="handled"
        ListEmptyComponent={
          query.trim().length >= 2 && !loading ? (
            <Text style={styles.empty}>No users found.</Text>
          ) : query.trim().length === 1 ? (
            <Text style={styles.empty}>Type at least 2 letters…</Text>
          ) : null
        }
        ListHeaderComponent={
          loading ? <ActivityIndicator color={colors.muted} style={{ marginVertical: 12 }} /> : null
        }
        renderItem={({ item }) => (
          <View style={styles.row}>
            <Text style={styles.username}>{item.username}</Text>
            {renderButton(item)}
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: 16 },
  input: {
    backgroundColor: colors.card,
    color: colors.text,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 16,
    borderWidth: 1,
    borderColor: colors.border,
    marginBottom: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 14,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  username: { color: colors.text, fontSize: 17 },
  addBtn: { backgroundColor: colors.accent, borderRadius: 10, paddingHorizontal: 18, paddingVertical: 8 },
  addText: { color: colors.bg, fontWeight: '700' },
  tag: { color: colors.muted, fontSize: 14 },
  empty: { color: colors.muted, textAlign: 'center', marginTop: 40, fontSize: 16 },
  error: { color: colors.danger, textAlign: 'center', marginBottom: 10 },
});
