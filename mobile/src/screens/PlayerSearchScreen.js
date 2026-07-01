import { useEffect, useRef, useState } from 'react';
import { FlatList, Keyboard, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { searchPlayers } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Avatar, Badge, EmptyState, SearchInput, SkeletonList } from '../components/ui';

const SPORT = { wnba: { label: 'WNBA', tone: 'info' }, mlb: { label: 'MLB', tone: 'warning' }, nba: { label: 'NBA', tone: 'info' }, nfl: { label: 'NFL', tone: 'neutral' } };

export default function PlayerSearchScreen({ navigation }) {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [query, setQuery] = useState('');
  const [players, setPlayers] = useState([]);
  const [loading, setLoading] = useState(false);
  const seq = useRef(0);

  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) {
      setPlayers([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    const mine = ++seq.current;
    const t = setTimeout(async () => {
      try {
        const res = await searchPlayers(token, q);
        if (mine === seq.current) setPlayers(res.players || []);
      } catch {
        if (mine === seq.current) setPlayers([]);
      } finally {
        if (mine === seq.current) setLoading(false);
      }
    }, 300);
    return () => clearTimeout(t);
  }, [query, token]);

  const q = query.trim();

  return (
    <Screen padded={false}>
      <View style={styles.searchWrap}>
        <SearchInput value={query} onChangeText={setQuery} placeholder="Search any player…" autoFocus />
      </View>

      {loading ? (
        <View style={{ paddingHorizontal: spacing.lg }}>
          <SkeletonList count={6} />
        </View>
      ) : (
        <FlatList
          data={players}
          keyExtractor={(item) => String(item.id)}
          keyboardShouldPersistTaps="handled"
          onScrollBeginDrag={Keyboard.dismiss}
          contentContainerStyle={{ paddingHorizontal: spacing.lg, paddingBottom: spacing.xl }}
          ListEmptyComponent={
            q.length < 2 ? (
              <EmptyState icon="search-outline" title="Scout any player" subtitle="Search WNBA and MLB players by name to see their season stats and fantasy game log." />
            ) : (
              <EmptyState icon="sad-outline" title="No players found" subtitle={`Nothing matches "${q}".`} />
            )
          }
          renderItem={({ item }) => {
            const s = SPORT[item.sport] || { label: item.sport?.toUpperCase(), tone: 'neutral' };
            return (
              <Pressable
                onPress={() => navigation.navigate('PlayerProfile', { id: item.id, name: item.name, team: item.team, position: item.position })}
                style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.card }]}
              >
                <Avatar name={item.name} size={40} />
                <View style={{ flex: 1, marginLeft: spacing.md }}>
                  <Text style={styles.name}>{item.name}</Text>
                  <View style={styles.metaRow}>
                    <Badge label={s.label} tone={s.tone} />
                    <Text style={styles.meta}>
                      {item.team} · {item.position}
                    </Text>
                  </View>
                </View>
                <View style={styles.fpgWrap}>
                  <Text style={styles.fpg}>{(item.projection ?? 0).toFixed(1)}</Text>
                  <Text style={styles.fpgLabel}>FPG</Text>
                </View>
                <Ionicons name="chevron-forward" size={16} color={colors.placeholder} style={{ marginLeft: 6 }} />
              </Pressable>
            );
          }}
        />
      )}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    searchWrap: { padding: spacing.lg, paddingBottom: spacing.sm },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.sm, borderRadius: radius.md },
    name: { color: colors.text, fontSize: font.subtitle, fontWeight: '700' },
    metaRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: 3 },
    meta: { color: colors.muted, fontSize: font.small },
    fpgWrap: { alignItems: 'center', minWidth: 40 },
    fpg: { color: colors.accent, fontSize: font.bodyLg, fontWeight: '800' },
    fpgLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
  });
