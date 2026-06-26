import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { listPlayers } from '../api/sports';
import { colors } from '../theme';

export default function PlayersScreen({ route }) {
  const { sport } = route.params;
  const { token } = useAuth();

  const [players, setPlayers] = useState([]);
  const [positions, setPositions] = useState([]);
  const [activePosition, setActivePosition] = useState(null); // null = All
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Re-fetch whenever the sport, search text, or position filter changes.
  // (Search text is debounced 300ms so we don't hit the server on every key.)
  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    const timer = setTimeout(async () => {
      try {
        const res = await listPlayers(token, {
          sport,
          q: query.trim(),
          position: activePosition,
        });
        if (cancelled) return;
        setPlayers(res.players);
        // Keep the full position list stable (only set it from an unfiltered load).
        if (!activePosition && !query.trim()) setPositions(res.positions);
        setError(null);
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
  }, [sport, query, activePosition, token]);

  const chips = [null, ...positions];

  return (
    <View style={styles.container}>
      <TextInput
        style={styles.input}
        placeholder="Search players"
        placeholderTextColor={colors.placeholder}
        autoCapitalize="none"
        autoCorrect={false}
        value={query}
        onChangeText={setQuery}
      />

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.chips}
      >
        {chips.map((pos) => {
          const active = pos === activePosition;
          return (
            <TouchableOpacity
              key={pos ?? 'all'}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => setActivePosition(pos)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {pos ?? 'All'}
              </Text>
            </TouchableOpacity>
          );
        })}
      </ScrollView>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading ? (
        <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: 30 }} />
      ) : (
        <FlatList
          data={players}
          keyExtractor={(item) => String(item.id)}
          keyboardShouldPersistTaps="handled"
          ListEmptyComponent={<Text style={styles.empty}>No players found.</Text>}
          renderItem={({ item }) => (
            <View style={styles.row}>
              <View style={{ flex: 1 }}>
                <Text style={styles.name}>{item.name}</Text>
                <Text style={styles.meta}>{item.team}</Text>
              </View>
              <View style={styles.posBadge}>
                <Text style={styles.posText}>{item.position}</Text>
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
  input: {
    backgroundColor: colors.card,
    color: colors.text,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 16,
    borderWidth: 1,
    borderColor: colors.border,
  },
  chips: { paddingVertical: 12, gap: 8 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 20,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  chipActive: { backgroundColor: colors.accent, borderColor: colors.accent },
  chipText: { color: colors.muted, fontWeight: '600' },
  chipTextActive: { color: colors.bg },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  name: { color: colors.text, fontSize: 17, fontWeight: '600' },
  meta: { color: colors.muted, fontSize: 13, marginTop: 2 },
  posBadge: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  posText: { color: colors.accent, fontWeight: '700', fontSize: 13 },
  empty: { color: colors.muted, textAlign: 'center', marginTop: 50, fontSize: 16 },
});
