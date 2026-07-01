import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listPlayers, getBoxScore } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, Avatar, Badge, SkeletonList, SectionHeader } from '../components/ui';

const GROUP_LABEL = { batting: 'Batting', pitching: 'Pitching', '': 'Box Score' };

export default function GameDetailScreen({ route, navigation }) {
  const { game, sport = 'wnba' } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const isLiveOrFinal = game.state === 'in' || game.state === 'post';

  if (isLiveOrFinal) {
    return <BoxScoreView game={game} sport={sport} token={token} styles={styles} colors={colors} />;
  }
  return <RosterView game={game} sport={sport} token={token} navigation={navigation} styles={styles} colors={colors} />;
}

// --- Live / final: the ESPN-style box score + a fantasy column --------------

function BoxScoreView({ game, sport, token, styles, colors }) {
  const [box, setBox] = useState(null);
  const [error, setError] = useState(null);
  const timer = useRef(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
        try {
          const res = await getBoxScore(token, sport, game.id);
          if (active) setBox(res);
        } catch (e) {
          if (active && !box) setError(e.message);
        }
      };
      tick();
      // Poll while the game is live.
      if (game.state === 'in') timer.current = setInterval(tick, 30000);
      return () => {
        active = false;
        if (timer.current) clearInterval(timer.current);
      };
    }, [token, sport, game.id, game.state])
  );

  if (error && !box) {
    return (
      <Screen>
        <MatchHeader game={game} styles={styles} />
        <Card>
          <Text style={styles.emptyRoster}>Box score unavailable right now.</Text>
        </Card>
      </Screen>
    );
  }

  if (!box) {
    return (
      <Screen>
        <MatchHeader game={game} styles={styles} />
        <SkeletonList count={8} />
      </Screen>
    );
  }

  const live = box.state === 'in';

  return (
    <Screen scroll>
      {/* Scoreboard */}
      <Card style={styles.scoreCard}>
        {box.teams.map((t) => (
          <View key={t.abbrev} style={styles.scoreLine}>
            <Text style={styles.scoreTeam}>{t.abbrev}</Text>
            <Text style={styles.scoreName} numberOfLines={1}>
              {t.name}
            </Text>
            <Text style={styles.scoreNum}>{t.score ?? '—'}</Text>
          </View>
        ))}
        <View style={styles.scoreStatus}>
          {live ? <Badge label="LIVE" tone="danger" dot /> : null}
          <Text style={styles.scoreStatusText}>{box.status}</Text>
        </View>
      </Card>

      {box.teams.map((t) => (
        <View key={t.abbrev}>
          <SectionHeader>{t.name}</SectionHeader>
          {t.groups.map((g, gi) =>
            g.rows.length === 0 ? null : (
              <View key={gi} style={{ marginBottom: spacing.md }}>
                {t.groups.length > 1 ? <Text style={styles.groupLabel}>{GROUP_LABEL[g.type] || g.type}</Text> : null}
                <BoxTable group={g} styles={styles} colors={colors} />
              </View>
            )
          )}
        </View>
      ))}

      {sport === 'mlb' && !((box.state === 'post')) ? (
        <Text style={styles.approxNote}>Fantasy is approximate mid-game (extra-base hits finalize after the game).</Text>
      ) : null}
    </Screen>
  );
}

function BoxTable({ group, styles, colors }) {
  return (
    <Card padded={false} style={{ overflow: 'hidden' }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View>
          {/* header */}
          <View style={[styles.bxRow, styles.bxHeadRow]}>
            <Text style={[styles.bxCell, styles.bxNameCell, styles.bxHeadText]}>PLAYER</Text>
            <Text style={[styles.bxCell, styles.bxFanCell, styles.bxHeadText, { color: colors.accent }]}>FAN</Text>
            {group.columns.map((c, i) => (
              <Text key={i} style={[styles.bxCell, styles.bxHeadText]}>
                {c}
              </Text>
            ))}
          </View>
          {group.rows.map((r, ri) => (
            <View key={`${r.name}-${ri}`} style={[styles.bxRow, ri < group.rows.length - 1 && styles.bxDivider]}>
              <Text style={[styles.bxCell, styles.bxNameCell, styles.bxName]} numberOfLines={1}>
                {r.starter ? '' : '  '}
                {r.name}
              </Text>
              <Text style={[styles.bxCell, styles.bxFanCell, styles.bxFan]}>{r.fantasy}</Text>
              {r.stats.map((s, i) => (
                <Text key={i} style={[styles.bxCell, styles.bxStat]}>
                  {s}
                </Text>
              ))}
            </View>
          ))}
        </View>
      </ScrollView>
    </Card>
  );
}

// --- Upcoming: the draftable rosters + projections --------------------------

function RosterView({ game, sport, token, navigation, styles, colors }) {
  const [rosters, setRosters] = useState({ away: [], home: [] });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const [away, home] = await Promise.all([
          listPlayers(token, { sport, team: game.away.abbrev }),
          listPlayers(token, { sport, team: game.home.abbrev }),
        ]);
        if (active) setRosters({ away: away.players, home: home.players });
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [token, sport]);

  function openPlayer(p) {
    navigation.navigate('PlayerProfile', { id: p.id, name: p.name, team: p.team, position: p.position });
  }

  function Roster({ title, players }) {
    return (
      <View style={{ marginTop: spacing.lg }}>
        <SectionHeader style={{ marginTop: 0 }}>{title}</SectionHeader>
        <Card padded={false}>
          {players.length === 0 ? (
            <Text style={styles.emptyRoster}>Roster unavailable.</Text>
          ) : (
            players.map((p, i) => (
              <Pressable
                key={p.id}
                onPress={() => openPlayer(p)}
                style={({ pressed }) => [styles.row, i < players.length - 1 && styles.divider, pressed && { backgroundColor: colors.bgElevated }]}
              >
                <Avatar name={p.name} size={36} />
                <View style={{ flex: 1, marginLeft: spacing.md }}>
                  <Text style={styles.name}>{p.name}</Text>
                  <Text style={styles.meta}>{p.position}</Text>
                </View>
                <View style={styles.projWrap}>
                  <Text style={styles.proj}>{(p.projection ?? 0).toFixed(1)}</Text>
                  <Text style={styles.projLabel}>FPG</Text>
                </View>
                <Ionicons name="chevron-forward" size={16} color={colors.placeholder} style={{ marginLeft: 8 }} />
              </Pressable>
            ))
          )}
        </Card>
      </View>
    );
  }

  return (
    <Screen scroll>
      <MatchHeader game={game} styles={styles} />
      {loading ? (
        <SkeletonList count={8} />
      ) : (
        <>
          <Roster title={game.away.name} players={rosters.away} />
          <Roster title={game.home.name} players={rosters.home} />
        </>
      )}
    </Screen>
  );
}

function MatchHeader({ game, styles }) {
  return (
    <View style={styles.matchup}>
      <Text style={styles.teams}>
        {game.away.abbrev} @ {game.home.abbrev}
      </Text>
      <Text style={styles.sub}>{game.status}</Text>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    matchup: { alignItems: 'center', marginBottom: spacing.sm },
    teams: { color: colors.text, fontSize: font.titleLg, fontWeight: '800' },
    sub: { color: colors.muted, fontSize: font.body, marginTop: 4 },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.lg },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    name: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 1 },
    projWrap: { alignItems: 'center', minWidth: 38 },
    proj: { color: colors.accent, fontSize: font.bodyLg, fontWeight: '800' },
    projLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
    emptyRoster: { color: colors.muted, padding: spacing.lg, textAlign: 'center' },

    // scoreboard
    scoreCard: { marginBottom: spacing.md },
    scoreLine: { flexDirection: 'row', alignItems: 'center', paddingVertical: 6 },
    scoreTeam: { color: colors.text, fontSize: font.bodyLg, fontWeight: '900', width: 52 },
    scoreName: { color: colors.muted, fontSize: font.body, flex: 1 },
    scoreNum: { color: colors.text, fontSize: font.title, fontWeight: '900', width: 44, textAlign: 'right' },
    scoreStatus: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, justifyContent: 'center', marginTop: spacing.sm },
    scoreStatusText: { color: colors.muted, fontSize: font.small, fontWeight: '700' },
    groupLabel: { color: colors.muted, fontSize: font.small, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: spacing.xs, marginLeft: 2 },
    approxNote: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.sm, marginBottom: spacing.lg },

    // box table
    bxRow: { flexDirection: 'row', alignItems: 'center' },
    bxHeadRow: { backgroundColor: colors.bgElevated, paddingVertical: 8 },
    bxDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    bxCell: { width: 42, textAlign: 'center', color: colors.text, fontSize: font.caption, paddingVertical: 10 },
    bxHeadText: { color: colors.muted, fontSize: 10, fontWeight: '800', letterSpacing: 0.3 },
    bxNameCell: { width: 132, textAlign: 'left', paddingLeft: spacing.md },
    bxName: { color: colors.text, fontSize: font.small, fontWeight: '600' },
    bxFanCell: { width: 48 },
    bxFan: { color: colors.accent, fontWeight: '800', fontSize: font.small },
    bxStat: { color: colors.muted },
  });
