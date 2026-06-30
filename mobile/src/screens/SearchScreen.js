import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { searchUsers, sendFriendRequest } from '../api/social';
import { colors, spacing, font } from '../theme';
import { Screen, Avatar, Button, Badge, EmptyState, SearchInput } from '../components/ui';

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
    setResults((prev) => prev.map((u) => (u.id === user.id ? { ...u, relationship: 'request_sent' } : u)));
    try {
      await sendFriendRequest(token, user.id);
    } catch (e) {
      setError(e.message);
      setResults((prev) => prev.map((u) => (u.id === user.id ? { ...u, relationship: 'none' } : u)));
    }
  }

  function renderAction(user) {
    switch (user.relationship) {
      case 'friends':
        return <Badge label="Friends" tone="accent" />;
      case 'request_sent':
        return <Badge label="Requested" tone="info" />;
      case 'request_received':
        return <Badge label="Wants to add you" tone="warning" />;
      default:
        return <Button title="Add" size="sm" full={false} icon="person-add" onPress={() => add(user)} />;
    }
  }

  const trimmed = query.trim();

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <SearchInput value={query} onChangeText={setQuery} placeholder="Search by username" autoFocus />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <FlatList
          data={results}
          keyExtractor={(item) => String(item.id)}
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={{ paddingTop: spacing.sm, flexGrow: 1 }}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListHeaderComponent={loading ? <ActivityIndicator color={colors.muted} style={{ marginVertical: spacing.md }} /> : null}
          ListEmptyComponent={
            trimmed.length >= 2 && !loading ? (
              <EmptyState icon="search" title="No users found" subtitle="Double-check the spelling and try again." />
            ) : trimmed.length === 1 ? (
              <EmptyState icon="text-outline" title="Keep typing" subtitle="Enter at least 2 letters to search." />
            ) : (
              <EmptyState icon="person-add-outline" title="Find your friends" subtitle="Search by username to send a friend request." />
            )
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Avatar name={item.username} size={44} />
              <Text style={styles.username}>{item.username}</Text>
              {renderAction(item)}
            </View>
          )}
        />
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
  username: { color: colors.text, fontSize: font.subtitle, fontWeight: '600', marginLeft: spacing.md, flex: 1 },
  error: { color: colors.danger, textAlign: 'center', marginVertical: spacing.sm },
});
