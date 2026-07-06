import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { listPlayers, getBoxScore } from '../api/sports';
import { useTheme, useThemedStyles, spacing, fonts, font, withAlpha } from '../theme';
import { Screen, Card, Avatar, Badge, SkeletonList, SectionHeader, GhostText, Kicker, CondTitle } from '../components/ui';

const GROUP_LABEL = { batting: 'BATTING', pitching: 'PITCHING', '': 'BOX SCORE' };
const fan = (v) => Number(v) || 0;

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

// The marquee scoreboard hero: big condensed scores, live pulse, VS watermark.
function ScoreHero({ teams, live, status, styles, colors }) {
  const [a, h] = teams;
  const aScore = fan(a?.score);
  const hScore = fan(h?.score);
  return (
    <LinearGradient colors={[colors.cardElevated, colors.card]} style={styles.hero}>
      <View style={styles.heroGhost} pointerEvents="none">
        <GhostText size={64} color={withAlpha(colors.text, 0.07)} strokeWidth={1}>
          VS
        </GhostText>
      </View>
      <View style={styles.heroTop}>
        <Kicker size={9} tracking={2}>
          Head-to-head · real game
        </Kicker>
        {live ? <Badge label="Live" tone="danger" blink /> : <Badge label="Final" tone="neutral" />}
      </View>
      {[a, h].map((t, i) => {
        const mine = i === 0 ? aScore : hScore;
        const other = i === 0 ? hScore : aScore;
        const leads = mine > other;
        return (
          <View key={t.abbrev} style={styles.heroLine}>
            <Text style={[styles.heroAbbrev, !leads && { color: colors.muted }]}>{t.abbrev}</Text>
            <Text style={styles.heroName} numberOfLines={1}>
              {t.name}
            </Text>
            <Text style={[styles.heroScore, leads && { color: colors.accent }]}>{t.score ?? '—'}</Text>
          </View>
        );
      })}
      <Text style={styles.heroStatus}>{status}</Text>
    </LinearGradient>
  );
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
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [token, sport, game.id, game.state])
  );

  if (error && !box) {
    return (
      <Screen>
        <Card>
          <Text style={styles.emptyRoster}>Box score unavailable right now.</Text>
        </Card>
      </Screen>
    );
  }

  if (!box) {
    return (
      <Screen>
        <SkeletonList count={8} />
      </Screen>
    );
  }

  const live = box.state === 'in';

  // Best fantasy nights across both rosters — who's actually cooking.
  const heaters = box.teams
    .flatMap((t) => t.groups.flatMap((g) => g.rows.map((r) => ({ ...r, team: t.abbrev }))))
    .filter((r) => fan(r.fantasy) > 0)
    .sort((x, y) => fan(y.fantasy) - fan(x.fantasy))
    .slice(0, 3);

  return (
    <Screen scroll>
      <ScoreHero teams={box.teams} live={live} status={box.status} styles={styles} colors={colors} />

      {heaters.length > 0 ? (
        <>
          <View style={styles.heatHead}>
            <Kicker size={9} tracking={2}>
              {live ? 'Heating up' : 'Best fantasy nights'}
            </Kicker>
            <Kicker size={9} tracking={2}>
              Fan pts
            </Kicker>
          </View>
          <View style={styles.heatRow}>
            {heaters.map((r, i) => (
              <View key={`${r.name}-${i}`} style={[styles.heatCard, i === 0 && styles.heatCardTop]}>
                <Avatar name={r.name} size={30} />
                <Text style={styles.heatName} numberOfLines={1}>
                  {r.name}
                </Text>
                <Text style={styles.heatTeam}>{r.team}</Text>
                <CondTitle size={22} color={i === 0 ? colors.accent : colors.text}>
                  {r.fantasy}
                </CondTitle>
              </View>
            ))}
          </View>
        </>
      ) : null}

      {box.teams.map((t) => (
        <View key={t.abbrev}>
          <SectionHeader>{t.name}</SectionHeader>
          {t.groups.map((g, gi) =>
            g.rows.length === 0 ? null : (
              <View key={gi} style={{ marginBottom: spacing.md }}>
                {t.groups.length > 1 ? (
                  <Kicker size={9} tracking={1.5} style={{ marginBottom: 5, marginLeft: 2 }}>
                    {GROUP_LABEL[g.type] || g.type}
                  </Kicker>
                ) : null}
                <BoxTable group={g} styles={styles} colors={colors} />
              </View>
            )
          )}
        </View>
      ))}

      {sport === 'mlb' && !(box.state === 'post') ? (
        <Text style={styles.approxNote}>Fantasy is approximate mid-game (extra-base hits finalize after the game).</Text>
      ) : null}
    </Screen>
  );
}

function BoxTable({ group, styles, colors }) {
  // The best fantasy line in the table gets the lime row treatment.
  const best = group.rows.reduce((m, r) => Math.max(m, fan(r.fantasy)), 0);
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
          {group.rows.map((r, ri) => {
            const hot = best > 0 && fan(r.fantasy) === best;
            return (
              <View
                key={`${r.name}-${ri}`}
                style={[styles.bxRow, ri < group.rows.length - 1 && styles.bxDivider, hot && { backgroundColor: withAlpha(colors.accent, 0.05) }]}
              >
                <Text style={[styles.bxCell, styles.bxNameCell, styles.bxName, !r.starter && { color: colors.muted }]} numberOfLines={1}>
                  {r.name}
                </Text>
                <Text style={[styles.bxCell, styles.bxFanCell, styles.bxFan]}>{r.fantasy}</Text>
                {r.stats.map((s, i) => (
                  <Text key={i} style={[styles.bxCell, styles.bxStat]}>
                    {s}
                  </Text>
                ))}
              </View>
            );
          })}
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, sport]);

  function openPlayer(p) {
    navigation.navigate('PlayerProfile', { id: p.id, name: p.name, team: p.team, position: p.position });
  }

  function Roster({ title, players }) {
    return (
      <View style={{ marginTop: spacing.md }}>
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
                  <Text style={styles.projLabel}>PROJ</Text>
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
      <View style={styles.matchup}>
        <CondTitle size={30} style={{ paddingRight: 4 }}>
          {game.away.abbrev} <Text style={{ color: colors.placeholder }}>@</Text> {game.home.abbrev}
        </CondTitle>
        <Text style={styles.matchSub}>{game.status}</Text>
        <Kicker size={9} tracking={2} style={{ marginTop: 6 }}>
          Scout both rosters before tip
        </Kicker>
      </View>
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

const makeStyles = (colors) =>
  StyleSheet.create({
    matchup: { alignItems: 'center', marginBottom: spacing.sm },
    matchSub: { color: colors.muted, fontSize: 12, fontFamily: fonts.bodySemi, marginTop: 4 },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.lg },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    name: { color: colors.text, fontSize: 13.5, fontFamily: fonts.bodyBold },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 1, fontFamily: fonts.body },
    projWrap: { alignItems: 'flex-end', minWidth: 40 },
    proj: { color: colors.accent, fontSize: 19, fontFamily: fonts.hero, lineHeight: 20 },
    projLabel: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    emptyRoster: { color: colors.muted, padding: spacing.lg, textAlign: 'center', fontFamily: fonts.body },

    // scoreboard hero
    hero: {
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      paddingHorizontal: 16,
      paddingVertical: 13,
      marginBottom: spacing.md,
      overflow: 'hidden',
    },
    heroGhost: { position: 'absolute', right: -4, top: -12 },
    heroTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 },
    heroLine: { flexDirection: 'row', alignItems: 'center', paddingVertical: 4 },
    heroAbbrev: { color: colors.text, fontFamily: fonts.heroUpright, fontSize: 20, width: 62, letterSpacing: 0.5 },
    heroName: { color: colors.muted, fontSize: 12, fontFamily: fonts.bodySemi, flex: 1 },
    heroScore: { color: colors.text, fontFamily: fonts.hero, fontSize: 40, lineHeight: 42, paddingRight: 4 },
    heroStatus: { color: colors.muted, fontFamily: fonts.condBold, fontSize: 13, textAlign: 'center', marginTop: 6, letterSpacing: 0.5 },

    // heaters
    heatHead: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6, paddingHorizontal: 2 },
    heatRow: { flexDirection: 'row', gap: 8 },
    heatCard: {
      flex: 1,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      paddingVertical: 10,
      alignItems: 'center',
      gap: 3,
    },
    heatCardTop: { borderColor: withAlpha(colors.accent, 0.4), backgroundColor: withAlpha(colors.accent, 0.06) },
    heatName: { color: colors.text, fontSize: 10.5, fontFamily: fonts.bodyBold, maxWidth: '90%' },
    heatTeam: { color: colors.placeholder, fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },

    // box table
    bxRow: { flexDirection: 'row', alignItems: 'center' },
    bxHeadRow: { backgroundColor: colors.cardElevated, paddingVertical: 7 },
    bxDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    bxCell: { width: 42, textAlign: 'center', color: colors.text, fontSize: font.caption, paddingVertical: 10 },
    bxHeadText: { color: colors.muted, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
    bxNameCell: { width: 132, textAlign: 'left', paddingLeft: spacing.md },
    bxName: { color: colors.text, fontSize: font.small, fontFamily: fonts.bodySemi },
    bxFanCell: { width: 48 },
    bxFan: { color: colors.accent, fontFamily: fonts.heroUpright, fontSize: 15 },
    bxStat: { color: colors.muted, fontFamily: fonts.condMedium, fontSize: 13 },
    approxNote: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.sm, marginBottom: spacing.lg, fontFamily: fonts.body },
  });
