import { useEffect, useState } from 'react';
import { FlatList, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { listPlayers } from '../api/sports';
import { useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList, SearchInput, Chip, FadeIn } from '../components/ui';

export default function PlayersScreen({ route }) {
  const { sport } = route.params;
  const { token } = useAuth();
  const styles = useThemedStyles(makeStyles);

  const [players, setPlayers] = useState([]);
  const [positions, setPositions] = useState([]);
  const [activePosition, setActivePosition] = useState(null); // null = All
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    const timer = setTimeout(async () => {
      try {
        const res = await listPlayers(token, { sport, q: query.trim(), position: activePosition });
        if (cancelled) return;
        setPlayers(res.players);
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
    <Screen padded={false}>
      <View style={styles.header}>
        <SearchInput value={query} onChangeText={setQuery} placeholder="Search players" />
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, flexShrink: 0 }} contentContainerStyle={styles.chips}>
          {chips.map((pos) => (
            <Chip key={pos ?? 'all'} label={pos ?? 'All'} active={pos === activePosition} onPress={() => setActivePosition(pos)} />
          ))}
        </ScrollView>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading ? (
        <View style={{ paddingHorizontal: spacing.lg }}>
          <SkeletonList count={8} />
        </View>
      ) : (
        <FlatList
          data={players}
          keyExtractor={(item) => String(item.id)}
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={{ paddingHorizontal: spacing.lg, paddingBottom: spacing.xl }}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListEmptyComponent={<EmptyState icon="search" title="No players found" subtitle="Try a different name or position filter." />}
          renderItem={({ item, index }) => (
            <FadeIn index={index}>
              <View style={styles.row}>
              <Text style={styles.rank}>{index + 1}</Text>
              <Avatar name={item.name} size={40} />
              <View style={{ flex: 1, marginLeft: spacing.md }}>
                <Text style={styles.name}>{item.name}</Text>
                <Text style={styles.meta}>{item.team}</Text>
              </View>
              {item.projection != null ? (
                <View style={styles.projWrap}>
                  <Text style={styles.proj}>{Math.round(item.projection)}</Text>
                  <Text style={styles.projLabel}>PROJ</Text>
                </View>
              ) : null}
              <View style={styles.posBadge}>
                <Text style={styles.posText}>{item.position}</Text>
              </View>
              </View>
            </FadeIn>
          )}
        />
      )}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    header: { paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    chips: { paddingVertical: spacing.md, gap: spacing.sm },
    error: { color: colors.danger, textAlign: 'center', marginVertical: spacing.md },
    sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
    rank: { color: colors.placeholder, fontSize: font.small, fontWeight: '700', width: 22 },
    name: { color: colors.text, fontSize: font.subtitle, fontWeight: '600' },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    projWrap: { alignItems: 'center', marginRight: spacing.md },
    proj: { color: colors.accent, fontWeight: '800', fontSize: font.bodyLg },
    projLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
    posBadge: {
      backgroundColor: colors.accentSoft,
      borderColor: colors.accentBorder,
      borderWidth: 1,
      borderRadius: radius.sm,
      paddingHorizontal: 10,
      paddingVertical: 4,
      minWidth: 38,
      alignItems: 'center',
    },
    posText: { color: colors.accent, fontWeight: '700', fontSize: font.small },
  });
