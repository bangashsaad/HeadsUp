import { useCallback, useState } from 'react';
import { SectionList, StyleSheet, Text, View, Pressable } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { listUpcomingGames } from '../api/sports';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Badge, EmptyState, SkeletonList, Segmented, BlinkDot } from '../components/ui';

const WEEK = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const MON = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

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
    let title = `${WEEK[e.getUTCDay()]} ${MON[e.getUTCMonth()]} ${e.getUTCDate()}`;
    if (key === todayKey) title = `TONIGHT · ${title}`;
    else if (key === tomKey) title = `TOMORROW · ${title}`;
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

  // Refresh on focus and keep polling — live scores move while you watch.
  useFocusEffect(
    useCallback(() => {
      load();
      const iv = setInterval(load, 30000);
      return () => clearInterval(iv);
    }, [load])
  );

  function switchSport(next) {
    if (next === sport) return;
    setGames([]);
    setLoading(true);
    setSport(next);
  }

  return (
    <Screen padded={false}>
      <Segmented
        style={{ marginHorizontal: spacing.lg, marginTop: spacing.md }}
        value={sport}
        onChange={switchSport}
        options={SPORTS.map((s) => ({ key: s.key, label: s.label }))}
      />

      {loading ? (
        <View style={{ padding: spacing.lg }}>
          <SkeletonList count={6} />
        </View>
      ) : (
        <SectionList
          sections={buildSections(games)}
          keyExtractor={(item) => item.id}
          stickySectionHeadersEnabled={false}
          contentContainerStyle={{ padding: spacing.lg, paddingTop: spacing.xs, flexGrow: 1 }}
          showsVerticalScrollIndicator={false}
          onRefresh={() => {
            setRefreshing(true);
            load();
          }}
          refreshing={refreshing}
          ListEmptyComponent={
            error ? (
              <EmptyState icon="cloud-offline-outline" title="Couldn't load games" subtitle={error} />
            ) : (
              <EmptyState icon="calendar-outline" title="No upcoming games" subtitle="Check back when the next slate is scheduled." />
            )
          }
          renderSectionHeader={({ section }) => <Text style={styles.dayHeader}>{section.title}</Text>}
          renderItem={({ item }) => (
            <GameCard game={item} styles={styles} colors={colors} onPress={() => navigation.navigate('GameDetail', { game: item, sport })} />
          )}
        />
      )}
    </Screen>
  );
}

// One game. Live gets the red treatment; upcoming leads with the tip time.
function GameCard({ game, styles, colors, onPress }) {
  const live = game.state === 'in';
  const final = game.state === 'post';
  const showScore = live || final;
  const away = Number(game.away.score);
  const home = Number(game.home.score);

  const inner = (
    <View style={styles.gameInner}>
      <View style={{ flex: 1 }}>
        <TeamLine side={game.away} score={showScore ? game.away.score : null} winner={showScore && away > home} dim={final && away < home} styles={styles} colors={colors} />
        <View style={{ height: 7 }} />
        <TeamLine side={game.home} score={showScore ? game.home.score : null} winner={showScore && home > away} dim={final && home < away} styles={styles} colors={colors} />
      </View>
      <View style={styles.gameMeta}>
        {live ? (
          <>
            <Badge label="Live" tone="danger" blink />
            <Text style={styles.liveStatus} numberOfLines={1}>
              {game.status}
            </Text>
          </>
        ) : final ? (
          <Badge label="Final" tone="neutral" />
        ) : (
          <Text style={styles.gameTime}>{timeLabel(game.date)}</Text>
        )}
      </View>
    </View>
  );

  if (live) {
    return (
      <Pressable onPress={onPress} style={({ pressed }) => [pressed && { transform: [{ scale: 0.98 }] }]}>
        <LinearGradient
          colors={[withAlpha(colors.danger, 0.1), colors.card]}
          start={{ x: 0, y: 0 }}
          end={{ x: 0.9, y: 1 }}
          style={[styles.game, { borderColor: colors.dangerBorder }]}
        >
          {inner}
        </LinearGradient>
      </Pressable>
    );
  }

  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.game, final && { opacity: 0.85 }, pressed && { transform: [{ scale: 0.98 }] }]}>
      {inner}
    </Pressable>
  );
}

function TeamLine({ side, score, winner, dim, styles, colors }) {
  return (
    <View style={styles.teamLine}>
      <Text style={[styles.teamAbbrev, dim && { color: colors.muted }]}>{side.abbrev}</Text>
      <Text style={styles.teamName} numberOfLines={1}>
        {side.name}
      </Text>
      {score != null ? <Text style={[styles.score, winner && { color: colors.accent }, dim && { color: colors.muted }]}>{score}</Text> : null}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    dayHeader: {
      color: colors.placeholder,
      fontSize: 10,
      fontFamily: fonts.bodyExtra,
      letterSpacing: 2,
      marginTop: spacing.lg,
      marginBottom: spacing.sm,
    },
    game: {
      borderRadius: 14,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      padding: 13,
      marginBottom: spacing.sm,
      overflow: 'hidden',
    },
    gameInner: { flexDirection: 'row', alignItems: 'center' },
    teamLine: { flexDirection: 'row', alignItems: 'center' },
    teamAbbrev: { color: colors.text, fontFamily: fonts.heroUpright, fontSize: 17, width: 52, letterSpacing: 0.5 },
    teamName: { color: colors.muted, fontSize: 12, fontFamily: fonts.bodySemi, flex: 1 },
    score: { color: colors.text, fontFamily: fonts.hero, fontSize: 22, lineHeight: 24, marginLeft: spacing.sm, paddingRight: 3 },
    gameMeta: { marginLeft: spacing.md, alignItems: 'flex-end', minWidth: 70, gap: 4 },
    gameTime: { color: colors.accent, fontFamily: fonts.condBold, fontSize: 15, textAlign: 'right' },
    liveStatus: { color: colors.muted, fontFamily: fonts.condBold, fontSize: 12, maxWidth: 90, textAlign: 'right' },
  });
