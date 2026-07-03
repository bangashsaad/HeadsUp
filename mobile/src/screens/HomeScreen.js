import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View, Pressable, RefreshControl } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getHome } from '../api/me';
import { listUpcomingGames } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, Avatar, Badge, Button, SkeletonList } from '../components/ui';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

// Games whose ET wall-clock day is today.
function todays(games) {
  const now = new Date(Date.now() - 4 * 3600 * 1000);
  const key = (d) => `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
  const todayKey = key(now);
  return (games || []).filter((g) => key(new Date(new Date(g.date).getTime() - 4 * 3600 * 1000)) === todayKey);
}

export default function HomeScreen({ navigation }) {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [home, setHome] = useState(null);
  const [games, setGames] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    // Dashboard (DB-only, fast) drives the screen; games load separately so the
    // ESPN-backed schedule never blocks the landing content.
    try {
      const h = await getHome(token);
      setHome(h);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }

    Promise.all([
      listUpcomingGames(token, 'wnba').catch(() => ({ games: [] })),
      listUpcomingGames(token, 'mlb').catch(() => ({ games: [] })),
    ]).then(([wnba, mlb]) => {
      setGames([...todays(wnba.games), ...todays(mlb.games)].sort((a, b) => new Date(a.date) - new Date(b.date)));
    });
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function openDuel(id) {
    navigation.navigate('DuelsTab', { screen: 'DuelDetail', params: { id }, initial: false });
  }

  if (loading) {
    return (
      <Screen>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  const rec = home?.record || {};
  const actions = [
    ...(home?.needs_response || []).map((d) => ({ d, verb: 'Respond to', tone: 'info', icon: 'mail-unread-outline' })),
    ...(home?.draft_ready || []).map((d) => ({
      d,
      verb: d.status === 'drafting' ? 'Resume draft vs' : 'Draft vs',
      tone: 'accent',
      icon: 'flame',
    })),
  ];

  return (
    <Screen padded={false}>
      <ScrollView
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: spacing.xxl }}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor={colors.accent} />}
      >
        {/* Greeting + record */}
        <View style={styles.greetRow}>
          <View style={{ flex: 1 }}>
            <Text style={styles.hi}>Hey {user?.username} 👋</Text>
            <RecordLine rec={rec} styles={styles} colors={colors} />
          </View>
          <Avatar name={user?.username || '?'} size={48} />
        </View>

        {/* Action items */}
        <Text style={styles.sectionLabel}>Your move</Text>
        {actions.length === 0 ? (
          <Card style={styles.calmCard}>
            <Text style={styles.calmText}>You're all caught up. Challenge a friend to get a duel going.</Text>
            <Button title="New Challenge" icon="add" onPress={() => navigation.navigate('DuelsTab', { screen: 'CreateChallenge', initial: false })} />
          </Card>
        ) : (
          actions.map(({ d, verb, tone, icon }) => (
            <Pressable key={`act-${d.id}`} onPress={() => openDuel(d.id)} style={({ pressed }) => [styles.actionCard, pressed && { opacity: 0.85 }]}>
              <View style={[styles.actionIcon, { backgroundColor: colors.accentSoft }]}>
                <Ionicons name={icon} size={20} color={colors.accent} />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={styles.actionTitle}>
                  {verb} {d.opponent.username}
                </Text>
                <Text style={styles.actionSub}>
                  {SPORT_EMOJI[d.sport] || '🎯'} {d.roster_size} players
                </Text>
              </View>
              <Badge label={d.status === 'drafting' ? 'Live' : d.status === 'pending' ? 'Respond' : 'Ready'} tone={tone} />
              <Ionicons name="chevron-forward" size={18} color={colors.placeholder} style={{ marginLeft: spacing.xs }} />
            </Pressable>
          ))
        )}

        {(home?.awaiting || []).length > 0 ? (
          <Text style={styles.awaiting}>
            ⏳ {home.awaiting.length} duel{home.awaiting.length > 1 ? 's' : ''} awaiting final scores
          </Text>
        ) : null}

        {/* Recent results */}
        {(home?.recent_results || []).length > 0 ? (
          <>
            <Text style={styles.sectionLabel}>Latest results</Text>
            <Card padded={false}>
              {home.recent_results.map((d, i) => (
                <Pressable
                  key={`res-${d.id}`}
                  onPress={() => navigation.navigate('DuelsTab', { screen: 'Results', params: { id: d.id, opponentName: d.opponent.username }, initial: false })}
                  style={({ pressed }) => [styles.resultRow, i < home.recent_results.length - 1 && styles.divider, pressed && { backgroundColor: colors.bgElevated }]}
                >
                  <Badge label={d.my_outcome === 'win' ? 'Won' : d.my_outcome === 'tie' ? 'Tie' : 'Lost'} tone={d.my_outcome === 'win' ? 'accent' : d.my_outcome === 'tie' ? 'neutral' : 'danger'} />
                  <Text style={styles.resultText}>vs {d.opponent.username}</Text>
                  <Ionicons name="chevron-forward" size={16} color={colors.placeholder} />
                </Pressable>
              ))}
            </Card>
          </>
        ) : null}

        {/* Tonight's games */}
        <View style={styles.gamesHead}>
          <Text style={[styles.sectionLabel, { marginBottom: 0 }]}>Today's games</Text>
          <Pressable onPress={() => navigation.navigate('GamesTab')} hitSlop={8}>
            <Text style={styles.seeAll}>See all</Text>
          </Pressable>
        </View>
        {games.length === 0 ? (
          <Card>
            <Text style={styles.calmText}>No games on the slate today. Check the Games tab for what's coming up.</Text>
          </Card>
        ) : (
          <Card padded={false}>
            {games.slice(0, 6).map((g, i) => (
              <View key={g.id} style={[styles.gameRow, i < Math.min(games.length, 6) - 1 && styles.divider]}>
                <Text style={styles.gameTeams}>
                  {g.away.abbrev} @ {g.home.abbrev}
                </Text>
                <Text style={styles.gameStatus}>{g.status}</Text>
              </View>
            ))}
          </Card>
        )}
      </ScrollView>
    </Screen>
  );
}

function RecordLine({ rec, styles, colors }) {
  const tone = (l) => (l === 'W' ? colors.accent : l === 'L' ? colors.danger : colors.muted);
  const streak = rec.streak && rec.streak.count > 0 ? `${rec.streak.type === 'win' ? '🔥 W' : rec.streak.type === 'loss' ? 'L' : 'T'}${rec.streak.count}` : null;
  return (
    <View style={styles.recRow}>
      <Text style={styles.recText}>
        {rec.wins ?? 0}-{rec.losses ?? 0}
        {rec.ties ? `-${rec.ties}` : ''}
      </Text>
      {streak ? <Text style={styles.streak}>{streak}</Text> : null}
      <View style={{ flexDirection: 'row', marginLeft: spacing.sm }}>
        {(rec.recent || []).map((l, i) => (
          <Text key={i} style={[styles.formDot, { color: tone(l) }]}>
            {l}
          </Text>
        ))}
      </View>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    greetRow: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg },
    hi: { color: colors.text, fontSize: font.title, fontWeight: '800' },
    recRow: { flexDirection: 'row', alignItems: 'center', marginTop: 4 },
    recText: { color: colors.muted, fontSize: font.body, fontWeight: '700' },
    streak: { color: colors.accent, fontSize: font.body, fontWeight: '800', marginLeft: spacing.sm },
    formDot: { fontSize: font.small, fontWeight: '900', marginLeft: 3 },
    sectionLabel: { color: colors.muted, fontSize: font.caption, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 1, marginTop: spacing.lg, marginBottom: spacing.sm },
    calmCard: { gap: spacing.md },
    calmText: { color: colors.muted, fontSize: font.body, marginBottom: spacing.sm },
    actionCard: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      borderRadius: radius.md,
      padding: spacing.md,
      marginBottom: spacing.sm,
    },
    actionIcon: { width: 38, height: 38, borderRadius: 12, alignItems: 'center', justifyContent: 'center', marginRight: spacing.md },
    actionTitle: { color: colors.text, fontSize: font.subtitle, fontWeight: '700' },
    actionSub: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    awaiting: { color: colors.muted, fontSize: font.small, marginTop: spacing.sm, textAlign: 'center' },
    resultRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.md, paddingHorizontal: spacing.lg },
    resultText: { color: colors.text, fontSize: font.body, fontWeight: '600', flex: 1 },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    gamesHead: { flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between' },
    seeAll: { color: colors.accent, fontSize: font.small, fontWeight: '700' },
    gameRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: spacing.md, paddingHorizontal: spacing.lg },
    gameTeams: { color: colors.text, fontSize: font.body, fontWeight: '700' },
    gameStatus: { color: colors.muted, fontSize: font.small },
  });
