import { useCallback, useEffect, useRef, useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { listPlayers, getBoxScore } from '../api/sports';
import { teamColor, initials } from '../utils/teamArt';
import ScoreFlash from '../components/ScoreFlash';
import { useTheme, useThemedStyles, spacing, fonts, font, withAlpha } from '../theme';
import { Screen, Card, Avatar, SkeletonList, SectionHeader, GhostText, Kicker, BlinkDot, CondTitle } from '../components/ui';

const GROUP_LABEL = { batting: 'BATTING', pitching: 'PITCHING', '': 'BOX SCORE' };
const fan = (v) => Number(v) || 0;

export default function GameDetailScreen({ route, navigation }) {
  const { game, sport = 'wnba' } = route.params;
  const { token } = useAuth();
  const { colors, scheme } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const isLiveOrFinal = game.state === 'in' || game.state === 'post';

  if (isLiveOrFinal) {
    return <BoxScoreView game={game} sport={sport} token={token} styles={styles} colors={colors} scheme={scheme} />;
  }
  return <RosterView game={game} sport={sport} token={token} navigation={navigation} styles={styles} colors={colors} scheme={scheme} />;
}

// ---------------------------------------------------------------------------
// The matchup hero: real crests with team-color glows, ghost logos + a ghost
// VS, flashing live scores (or the tip time before the game).
// ---------------------------------------------------------------------------

function MatchHero({ away, home, state, status, sport, tipTime, styles, colors, scheme }) {
  const aC = teamColor(away);
  const hC = teamColor(home);
  const live = state === 'in';
  const pre = state === 'pre';
  const a = Number(away.score) || 0;
  const h = Number(home.score) || 0;
  const ghost = scheme === 'dark' ? 0.09 : 0.05;

  return (
    <LinearGradient
      colors={[withAlpha(aC, 0.22), colors.card, withAlpha(hC, 0.22)]}
      locations={[0, 0.5, 1]}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
      style={styles.hero}
    >
      {away.logo ? <Image source={{ uri: away.logo }} style={[styles.heroGhostA, { opacity: ghost }]} /> : null}
      {home.logo ? <Image source={{ uri: home.logo }} style={[styles.heroGhostH, { opacity: ghost }]} /> : null}
      <View style={styles.heroVs} pointerEvents="none">
        <GhostText size={54} color={withAlpha(colors.text, 0.07)} strokeWidth={1}>
          VS
        </GhostText>
      </View>

      <View style={styles.heroTop}>
        <Kicker size={9} tracking={2}>
          {sport === 'mlb' ? 'MLB' : 'WNBA'} · Real game
        </Kicker>
        {live ? (
          <View style={styles.liveChip}>
            <BlinkDot color={colors.danger} size={5} period={1100} />
            <Text style={styles.liveChipText} numberOfLines={1}>
              LIVE · {status}
            </Text>
          </View>
        ) : pre ? (
          <View style={styles.preChip}>
            <Text style={styles.preChipText}>UPCOMING</Text>
          </View>
        ) : (
          <View style={styles.finalChip}>
            <Text style={styles.finalChipText}>FINAL</Text>
          </View>
        )}
      </View>

      <View style={styles.heroGrid}>
        <TeamCol side={away} styles={styles} />
        {pre ? (
          <View style={styles.heroCenterPre}>
            <Text style={styles.tipTime}>{tipTime}</Text>
            <Text style={styles.tipLabel}>{sport === 'mlb' ? 'FIRST PITCH · ET' : 'TIP-OFF · ET'}</Text>
          </View>
        ) : (
          <View style={styles.heroCenter}>
            <ScoreFlash value={away.score} size={46} color={a >= h ? colors.accent : colors.text} />
            <View style={{ minWidth: 34, alignItems: 'center' }}>
              {!live ? <Text style={styles.finalMid}>FINAL</Text> : null}
            </View>
            <ScoreFlash value={home.score} size={46} color={h >= a ? colors.accent : colors.text} />
          </View>
        )}
        <TeamCol side={home} styles={styles} />
      </View>
    </LinearGradient>
  );
}

function TeamCol({ side, styles }) {
  const c = teamColor(side);
  return (
    <View style={styles.teamCol}>
      {side.logo ? (
        <Image
          source={{ uri: side.logo }}
          style={{ width: 58, height: 58, shadowColor: c, shadowOpacity: 0.55, shadowRadius: 10, shadowOffset: { width: 0, height: 5 } }}
        />
      ) : null}
      <Text style={styles.teamColCode}>{side.abbrev}</Text>
      <Text style={styles.teamColName} numberOfLines={1}>
        {String(side.name || '').toUpperCase()}
      </Text>
    </View>
  );
}

// Per-period scores: quarters for hoops, innings for baseball, total last.
function LineScore({ away, home, sport, styles, colors }) {
  const n = Math.max(away.linescores?.length || 0, home.linescores?.length || 0);
  if (n === 0) return null;

  const label = (i) => (sport === 'mlb' ? String(i + 1) : i < 4 ? `Q${i + 1}` : `OT${i > 4 ? i - 3 : ''}`);
  const cols = Array.from({ length: n }, (_, i) => ({
    l: label(i),
    a: away.linescores?.[i] ?? '–',
    h: home.linescores?.[i] ?? '–',
  }));
  const aT = Number(away.score) || 0;
  const hT = Number(home.score) || 0;

  return (
    <View style={styles.lineWrap}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, height: 64 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 3, paddingHorizontal: 14 }}>
          <View style={[styles.lineCol, { alignItems: 'flex-start', marginRight: 8 }]}>
            <Text style={styles.lineHead}> </Text>
            <Text style={[styles.lineCell, { color: colors.placeholder }]}>{away.abbrev}</Text>
            <Text style={[styles.lineCell, { color: colors.placeholder }]}>{home.abbrev}</Text>
          </View>
          {cols.map((c, i) => (
            <View key={i} style={styles.lineCol}>
              <Text style={styles.lineHead}>{c.l}</Text>
              <Text style={styles.lineCell}>{String(c.a)}</Text>
              <Text style={styles.lineCell}>{String(c.h)}</Text>
            </View>
          ))}
          <View style={[styles.lineCol, { minWidth: 30 }]}>
            <Text style={styles.lineHead}>{sport === 'mlb' ? 'R' : 'T'}</Text>
            <Text style={[styles.lineCell, styles.lineTotal, aT >= hT && { color: colors.accent }]}>{away.score}</Text>
            <Text style={[styles.lineCell, styles.lineTotal, hT >= aT && { color: colors.accent }]}>{home.score}</Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
}

// --- Live / final: hero + fantasy leaders + the full box score --------------

function BoxScoreView({ game, sport, token, styles, colors, scheme }) {
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
  // The box is the fresh truth; the tapped game card fills any art gaps.
  const merge = (t, side) => ({ ...side, ...t, logo: t?.logo || side?.logo, color: t?.color || side?.color });
  const away = merge(box.teams[0], game.away);
  const home = merge(box.teams[1], game.home);

  // Best fantasy nights across both rosters — who's actually cooking.
  const heaters = box.teams
    .flatMap((t) => (t.groups || []).flatMap((g) => g.rows.map((r) => ({ ...r, team: t, columns: g.columns }))))
    .filter((r) => fan(r.fantasy) > 0)
    .sort((x, y) => fan(y.fantasy) - fan(x.fantasy))
    .slice(0, 3);

  return (
    <Screen scroll>
      <MatchHero away={away} home={home} state={box.state} status={box.status} sport={sport} styles={styles} colors={colors} scheme={scheme} />
      <LineScore away={away} home={home} sport={sport} styles={styles} colors={colors} />

      {heaters.length > 0 ? (
        <>
          <View style={styles.heatHead}>
            <Kicker size={9} tracking={2}>
              {live ? 'Fantasy leaders · live' : 'Best fantasy nights'}
            </Kicker>
            <Kicker size={9} tracking={2}>
              Fan pts
            </Kicker>
          </View>
          <View style={styles.heatRow}>
            {heaters.map((r, i) => {
              const c = teamColor(r.team);
              return (
                <View key={`${r.name}-${i}`} style={[styles.heatCard, { borderColor: withAlpha(c, 0.35) }]}>
                  <View style={[styles.heatAv, { backgroundColor: withAlpha(c, 0.22), borderColor: withAlpha(c, 0.5) }]}>
                    <Text style={styles.heatIni}>{initials(r.name)}</Text>
                  </View>
                  <Text style={styles.heatName} numberOfLines={1}>
                    {r.name}
                  </Text>
                  <Text style={styles.heatTeam}>{r.team.abbrev}</Text>
                  <CondTitle size={21} color={colors.accent}>
                    {r.fantasy}
                  </CondTitle>
                  <Text style={styles.heatLine} numberOfLines={1}>
                    {statSummary(r.columns, r.stats) || r.position || ''}
                  </Text>
                </View>
              );
            })}
          </View>
        </>
      ) : null}

      {box.teams.map((t, ti) => (
        <View key={t.abbrev}>
          <View style={styles.boxHead}>
            {(ti === 0 ? away : home).logo ? <Image source={{ uri: (ti === 0 ? away : home).logo }} style={{ width: 19, height: 19 }} /> : null}
            <Text style={styles.boxHeadText}>{String(t.name || '').toUpperCase()}</Text>
            <View style={styles.boxHeadRule} />
          </View>
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

// "24 PTS · 9 REB · 3 AST" from the box columns (hoops); baseball rows fall
// back to position, their columns don't summarize as neatly.
function statSummary(columns = [], stats = []) {
  const picks = ['PTS', 'REB', 'AST']
    .map((l) => {
      const i = columns.indexOf(l);
      return i >= 0 && stats[i] != null ? `${stats[i]} ${l}` : null;
    })
    .filter(Boolean);
  return picks.length >= 2 ? picks.join(' · ') : null;
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

// --- Upcoming: the tip-time hero + draftable rosters + projections -----------

function RosterView({ game, sport, token, navigation, styles, colors, scheme }) {
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
      <MatchHero
        away={game.away}
        home={game.home}
        state="pre"
        status={game.status}
        sport={sport}
        tipTime={tipLabel(game.date)}
        styles={styles}
        colors={colors}
        scheme={scheme}
      />
      <Kicker size={9} tracking={2} style={{ textAlign: 'center', marginBottom: spacing.sm }}>
        Scout both rosters before tip
      </Kicker>
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

// "7:30 PM" in ET from the game's UTC date (UTC-4, WNBA/MLB season).
function tipLabel(iso) {
  const e = new Date(new Date(iso).getTime() - 4 * 3600 * 1000);
  let h = e.getUTCHours();
  const m = e.getUTCMinutes();
  const ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${String(m).padStart(2, '0')} ${ap}`;
}

const makeStyles = (colors) =>
  StyleSheet.create({
    // hero
    hero: {
      borderRadius: 20,
      borderWidth: 1,
      borderColor: colors.border,
      overflow: 'hidden',
      padding: 15,
      paddingBottom: 16,
      marginBottom: spacing.md,
    },
    heroGhostA: { position: 'absolute', left: -44, top: -40, width: 190, height: 190 },
    heroGhostH: { position: 'absolute', right: -44, bottom: -48, width: 190, height: 190 },
    heroVs: { position: 'absolute', right: -2, top: -14 },
    heroTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 },
    liveChip: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 5,
      backgroundColor: withAlpha(colors.danger, 0.12),
      borderColor: colors.danger,
      borderWidth: 1,
      borderRadius: 999,
      paddingVertical: 2,
      paddingHorizontal: 9,
      maxWidth: 210,
    },
    liveChipText: { color: colors.danger, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    finalChip: {
      backgroundColor: colors.cardElevated,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: 999,
      paddingVertical: 2,
      paddingHorizontal: 9,
    },
    finalChipText: { color: colors.muted, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    preChip: {
      backgroundColor: withAlpha(colors.accent, 0.12),
      borderColor: withAlpha(colors.accent, 0.45),
      borderWidth: 1,
      borderRadius: 999,
      paddingVertical: 2,
      paddingHorizontal: 9,
    },
    preChipText: { color: colors.accent, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    heroGrid: { flexDirection: 'row', alignItems: 'center' },
    heroCenter: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10 },
    heroCenterPre: { flex: 1, alignItems: 'center', gap: 3 },
    finalMid: { color: colors.placeholder, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1.5 },
    tipTime: { color: colors.accent, fontFamily: fonts.hero, fontSize: 28, lineHeight: 30, paddingRight: 3 },
    tipLabel: { color: colors.placeholder, fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 2 },
    teamCol: { alignItems: 'center', gap: 2, width: 84 },
    teamColCode: { color: colors.text, fontFamily: fonts.hero, fontSize: 17, marginTop: 5, paddingRight: 2 },
    teamColName: { color: colors.muted, fontSize: 8.5, fontFamily: fonts.bodyExtra, letterSpacing: 1, maxWidth: 82 },

    // line score
    lineWrap: {
      borderRadius: 14,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      marginBottom: spacing.md,
      overflow: 'hidden',
      paddingVertical: 4,
    },
    lineCol: { alignItems: 'center', gap: 5, minWidth: 24, paddingHorizontal: 2 },
    lineHead: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 0.5, height: 11 },
    lineCell: { color: colors.textDim, fontFamily: fonts.condBold, fontSize: 12.5 },
    lineTotal: { fontSize: 13.5, color: colors.muted },

    // fantasy leader tiles
    heatHead: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6, paddingHorizontal: 2 },
    heatRow: { flexDirection: 'row', gap: 8, marginBottom: spacing.md },
    heatCard: {
      flex: 1,
      borderRadius: 14,
      borderWidth: 1,
      backgroundColor: colors.card,
      paddingVertical: 11,
      paddingHorizontal: 6,
      alignItems: 'center',
      gap: 4,
    },
    heatAv: { width: 38, height: 38, borderRadius: 12, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
    heatIni: { fontSize: 13, fontFamily: fonts.bodyExtra, color: colors.text },
    heatName: { color: colors.text, fontSize: 10.5, fontFamily: fonts.bodyBold, maxWidth: '94%', textAlign: 'center' },
    heatTeam: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 1.5 },
    heatLine: { color: colors.muted, fontSize: 8.5, fontFamily: fonts.body, maxWidth: '94%', textAlign: 'center' },

    // per-team box heads
    boxHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: spacing.md, marginBottom: spacing.sm },
    boxHeadText: { color: colors.text, fontFamily: fonts.hero, fontSize: 15, letterSpacing: 1, paddingRight: 2 },
    boxHeadRule: { flex: 1, height: StyleSheet.hairlineWidth, backgroundColor: colors.border },

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

    // rosters (upcoming)
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.lg },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    name: { color: colors.text, fontSize: 13.5, fontFamily: fonts.bodyBold },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 1, fontFamily: fonts.body },
    projWrap: { alignItems: 'flex-end', minWidth: 40 },
    proj: { color: colors.accent, fontSize: 19, fontFamily: fonts.hero, lineHeight: 20 },
    projLabel: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    emptyRoster: { color: colors.muted, padding: spacing.lg, textAlign: 'center', fontFamily: fonts.body },
  });
