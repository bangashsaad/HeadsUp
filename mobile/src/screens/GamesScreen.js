import { useCallback, useState } from 'react';
import { SectionList, StyleSheet, Text, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listUpcomingGames } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Badge, EmptyState, SkeletonList } from '../components/ui';

const WEEK = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Shift a UTC instant to ET wall-clock (UTC-4 all WNBA season), read via getUTC*.
function et(iso) {
  return new Date(new Date(iso).getTime() - 4 * 3600 * 1000);
}
function dayKey(d) {
  return `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
}
function timeLabel(iso) {
  const e = et(iso);
  let h = e.getUTCHours();
  const m = e.getUTCMinutes();
  const ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${String(m).padStart(2, '0')} ${ap} ET`;
}

function buildSections(games) {
  const now = new Date(Date.now() - 4 * 3600 * 1000);
  const todayKey = dayKey(now);
  const tomKey = dayKey(new Date(now.getTime() + 24 * 3600 * 1000));

  const byDay = new Map();
  for (const g of games) {
    const e = et(g.date);
    const key = dayKey(e);
    if (!byDay.has(key)) byDay.set(key, { e, items: [] });
    byDay.get(key).items.push(g);
  }

  return Array.from(byDay.values()).map(({ e, items }) => {
    const key = dayKey(e);
    let title = `${WEEK[e.getUTCDay()]}, ${MON[e.getUTCMonth()]} ${e.getUTCDate()}`;
    if (key === todayKey) title = `Today · ${title}`;
    else if (key === tomKey) title = `Tomorrow · ${title}`;
    return { title, data: items };
  });
}

const SPORTS = [
  { key: 'wnba', label: 'WNBA' },
  { key: 'mlb', label: 'MLB' },
];

export default function GamesScreen({ navigation }) {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [sport, setSport] = useState('wnba');
  const [games, setGames] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listUpcomingGames(token, sport);
      setGames(res.games || []);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token, sport]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function switchSport(next) {
    if (next === sport) return;
    setGames([]);
    setLoading(true);
    setSport(next);
  }

  const label = SPORTS.find((s) => s.key === sport)?.label || '';

  return (
    <Screen padded={false}>
      <View style={styles.segmentWrap}>
        <View style={styles.segment}>
          {SPORTS.map((s) => (
            <Pressable key={s.key} onPress={() => switchSport(s.key)} style={[styles.segTab, sport === s.key && styles.segTabOn]}>
              <Text style={[styles.segLabel, { color: sport === s.key ? colors.onAccent : colors.muted }]}>{s.label}</Text>
            </Pressable>
          ))}
        </View>
      </View>

      {loading ? (
        <View style={{ paddingHorizontal: spacing.lg }}>
          <SkeletonList count={6} />
        </View>
      ) : (
        <SectionList
          sections={buildSections(games)}
          keyExtractor={(item) => item.id}
          stickySectionHeadersEnabled={false}
          contentContainerStyle={{ padding: spacing.lg, paddingTop: spacing.sm, flexGrow: 1 }}
          showsVerticalScrollIndicator={false}
          onRefresh={() => {
            setRefreshing(true);
            load();
          }}
          refreshing={refreshing}
          ListHeaderComponent={<Text style={styles.intro}>Upcoming {label} games — tap one to scout both rosters.</Text>}
          ListEmptyComponent={
            error ? (
              <EmptyState icon="cloud-offline-outline" title="Couldn't load games" subtitle={error} />
            ) : (
              <EmptyState icon="calendar-outline" title="No upcoming games" subtitle="Check back when the next slate is scheduled." />
            )
          }
          renderSectionHeader={({ section }) => <Text style={styles.dayHeader}>{section.title}</Text>}
          renderItem={({ item }) => <GameRow game={item} styles={styles} onPress={() => navigation.navigate('GameDetail', { game: item, sport })} />}
        />
      )}
    </Screen>
  );
}

function GameRow({ game, styles, onPress }) {
  const live = game.state === 'in';
  const final = game.state === 'post';
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.game, pressed && { opacity: 0.85 }]}>
      <View style={{ flex: 1 }}>
        <TeamLine side={game.away} score={final || live ? game.away.score : null} styles={styles} />
        <View style={{ height: 6 }} />
        <TeamLine side={game.home} score={final || live ? game.home.score : null} styles={styles} atHome />
      </View>
      <View style={styles.gameMeta}>
        {live ? <Badge label="LIVE" tone="danger" dot /> : final ? <Badge label="Final" tone="neutral" /> : <Text style={styles.gameTime}>{timeLabel(game.date)}</Text>}
      </View>
    </Pressable>
  );
}

function TeamLine({ side, score, styles, atHome }) {
  return (
    <View style={styles.teamLine}>
      <Text style={styles.teamAbbrev}>{side.abbrev}</Text>
      <Text style={styles.teamName} numberOfLines={1}>
        {atHome ? '' : ''}
        {side.name}
      </Text>
      {score != null ? <Text style={styles.score}>{score}</Text> : null}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    segmentWrap: { paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    segment: {
      flexDirection: 'row',
      gap: spacing.xs,
      backgroundColor: colors.card,
      borderRadius: radius.md,
      padding: spacing.xs,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
    },
    segTab: { flex: 1, alignItems: 'center', paddingVertical: 10, borderRadius: radius.sm },
    segTabOn: { backgroundColor: colors.accent },
    segLabel: { fontSize: font.body, fontWeight: '700' },
    intro: { color: colors.muted, fontSize: font.body, marginBottom: spacing.md },
    dayHeader: {
      color: colors.muted,
      fontSize: font.caption,
      fontWeight: '800',
      textTransform: 'uppercase',
      letterSpacing: 1,
      marginTop: spacing.lg,
      marginBottom: spacing.sm,
    },
    game: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      borderRadius: radius.md,
      padding: spacing.md,
      marginBottom: spacing.sm,
    },
    teamLine: { flexDirection: 'row', alignItems: 'center' },
    teamAbbrev: { color: colors.text, fontWeight: '800', fontSize: font.body, width: 46 },
    teamName: { color: colors.muted, fontSize: font.body, flex: 1 },
    score: { color: colors.text, fontWeight: '800', fontSize: font.bodyLg, marginLeft: spacing.sm },
    gameMeta: { marginLeft: spacing.md, alignItems: 'flex-end', minWidth: 64 },
    gameTime: { color: colors.muted, fontSize: font.small, fontWeight: '600', textAlign: 'right' },
  });
