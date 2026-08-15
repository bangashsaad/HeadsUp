# Game detail — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Pre-game: start time, probable starters, team leaders, roster scout. Live/final: linescore, full box score per team with fantasy points per player, HEATERS (top fantasy performers), game leaders.

## The app's design language (real tokens, from `src/theme.js`)

Dark palette (the shipped look): bg `#0A0B10`, elevated `#0D0F16`, card `#12141D`,
card-elevated `#191C28`, border `#252A3A`, subtle border `#1A1E2B`, text `#F4F5F7`,
dim `#B9BECF`, muted `#8B91A7`, placeholder `#565D73`, **accent lime `#C8FF2E`**
(text on accent: `#0A0B10`), danger `#FF4557`, warning/gold `#FFB021`,
purple `#7C5CFF` (text `#9F8BFF`), cyan `#22E5FF`, pink `#FF4D8D`, green `#39D98A`.
A light palette exists too; dark is the default and the brand.

Type: **Archivo** (body, weights 400–900), **Archivo Black italic** (display —
wordmark, "YOU WIN.", ghost VS), **Barlow Condensed 800 italic** (hero — scores,
section titles, ALL-CAPS pill buttons). Shapes: 999px pill buttons/chips,
8/12/16/20px card radii, 1px borders. Status→color: drafting = red (blinks),
pending/countered = purple, accepted/settled = lime, live dots blink.

UI kit primitives the screens compose (from `src/components/ui/`):

- **Avatar** — Initials tile with a stable per-name tint. Rounded square ("squircle"), per the Reimagined language. (8-digit hex appends alpha.)
- **Badge** — Small uppercase status pill. `tone` is one of the keys in theme `tones`. `dot` shows a leading dot; `blink` makes it pulse (live things blink).
- **BlinkDot** — The little live dot. blink=false renders it steady.
- **Button** — Condensed-italic pill buttons — the Reimagined CTA voice (ENTER ROOM →).
- **Card** — A surface with depth — border + soft shadow. Pass onPress to make it tappable.
- **Chip** — A selectable pill (filters, toggles). Light selection haptic on tap. Mirrors the Segmented recipe: center the label and let Barlow Condensed keep its NATURAL line height — forcing a lineHeight clips the glyphs on iOS.
- **EmptyState** — Friendly centered placeholder: an icon coin, a title, a subtitle, and an optional action node (e.g. a Button).
- **FadeIn** — Fade + slide a list row in on mount, lightly staggered by its index.
- **Field** — Labeled text input with optional password show/hide, a valid ✓, and an error.
- **GhostText** — Outline-only display text — the big translucent "VS" / pick-number watermarks. Rendered as stroked SVG text (RN has no text-stroke). Defaults to a faint stroke of the theme's text color, so it reads in light mode too.
- **Marquee** — Endless horizontal ticker: renders `children` twice and slides one copy's width, looping seamlessly. `speed` is px/second.
- **Pulse** — A soft expanding halo behind its children — the design's pulsing CTA ring.
- **Screen** — Page wrapper: themed bg, keyboard avoidance, and an optional scroll view with pull-to-refresh. No safe-area insets by default (the header owns the top, the tab bar owns the bottom).
- **SearchInput** — Text field with a leading search icon and a clear (×) button.
- **SectionHeader** — Condensed-italic section title, e.g. "YOUR MOVE", with an optional right hint ("3 PENDING"). Accepts a plain string child for back-compat.
- **Segmented** — The ACTIVE | PAST switch: a recessed track with a lime active segment. options: [{ key, label, count }]
- **Skeleton** — A single pulsing placeholder bar.
- **StatTile** — One tile of the 4-up stat grid: big condensed-italic value over a tiny kicker.
- **Type** — The three voices of the Reimagined type system. Tiny 800-weight uppercase tracking label: "SEASON RECORD", "PICK 3 OF 10".

## The screen source (`src/screens/GameDetailScreen.js`)

```jsx
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
import PlayerAvatar from '../components/PlayerAvatar';

const GROUP_LABEL = { batting: 'BATTING', pitching: 'PITCHING', '': 'BOX SCORE' };
const fan = (v) => Number(v) || 0;

// Football joins WNBA and MLB as a live sport, so the per-sport wording is a
// lookup rather than another nested ternary.
const LEAGUE_LABEL = { mlb: 'MLB', wnba: 'WNBA', nfl: 'NFL' };
const START_LABEL = { mlb: 'FIRST PITCH · ET', wnba: 'TIP-OFF · ET', nfl: 'KICKOFF · ET' };

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
          {LEAGUE_LABEL[sport] || 'WNBA'} · Real game
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
            <Text style={styles.tipLabel}>{START_LABEL[sport] || 'TIP-OFF · ET'}</Text>
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
                  {r.headshot_url ? (
                    <PlayerAvatar
                      uri={r.headshot_url}
                      name={r.name}
                      size={38}
                      style={{ borderWidth: 1, borderColor: withAlpha(c, 0.5) }}
                    />
                  ) : (
                    <View style={[styles.heatAv, { backgroundColor: withAlpha(c, 0.22), borderColor: withAlpha(c, 0.5) }]}>
                      <Text style={styles.heatIni}>{initials(r.name)}</Text>
                    </View>
                  )}
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
                <PlayerAvatar uri={p.headshot_url} name={p.name} size={36} />
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
      <MatchupPreview away={game.away} home={game.home} sport={sport} styles={styles} colors={colors} />

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

// Pre-game preview. Baseball turns on the probable starter, so that's the
// headline; basketball has no equivalent lever, so it shows each side's
// statistical leaders instead. Renders nothing when ESPN has neither, rather
// than leaving an empty shell on screen.
function MatchupPreview({ away, home, sport, styles, colors }) {
  const pitchers = away?.probable || home?.probable;
  const leaders = (away?.leaders || []).length > 0 || (home?.leaders || []).length > 0;
  if (!pitchers && !leaders) return null;

  if (pitchers) {
    return (
      <View style={{ marginBottom: spacing.md }}>
        <SectionHeader style={{ marginTop: 0 }}>Probable starters</SectionHeader>
        <Card padded={false}>
          <View style={styles.spRow}>
            <Starter side={away} styles={styles} colors={colors} />
            <GhostText size={15} color={colors.textFaint} strokeWidth={1}>
              VS
            </GhostText>
            <Starter side={home} styles={styles} colors={colors} align="flex-end" />
          </View>
        </Card>
      </View>
    );
  }

  return (
    <View style={{ marginBottom: spacing.md }}>
      <SectionHeader style={{ marginTop: 0 }}>Team leaders</SectionHeader>
      <Card padded={false}>
        <LeaderBlock side={away} styles={styles} colors={colors} />
        <View style={styles.divider} />
        <LeaderBlock side={home} styles={styles} colors={colors} />
      </Card>
    </View>
  );
}

function Starter({ side, styles, colors, align = 'flex-start' }) {
  const p = side?.probable;
  return (
    <View style={[styles.spCol, { alignItems: align }]}>
      <Text style={styles.spTeam}>
        {side?.abbrev}
        {side?.record ? ` · ${side.record}` : ''}
      </Text>
      {p ? (
        <>
          <PlayerAvatar uri={p.headshot_url} name={p.name} size={46} style={{ marginVertical: 6 }} />
          <Text style={styles.spName} numberOfLines={1}>
            {p.short_name || p.name}
          </Text>
          <Text style={styles.spLine} numberOfLines={1}>
            {p.line || p.position || 'SP'}
          </Text>
        </>
      ) : (
        <Text style={[styles.spLine, { marginTop: 14 }]}>Starter TBA</Text>
      )}
    </View>
  );
}

function LeaderBlock({ side, styles, colors }) {
  const list = side?.leaders || [];
  return (
    <View style={styles.ldBlock}>
      <Text style={styles.spTeam}>
        {side?.abbrev}
        {side?.record ? ` · ${side.record}` : ''}
      </Text>
      {list.length === 0 ? (
        <Text style={styles.spLine}>No leaders posted yet.</Text>
      ) : (
        <View style={styles.ldRow}>
          {list.map((l) => (
            <View key={l.category} style={styles.ldItem}>
              <Text style={styles.ldCat}>{l.category}</Text>
              <Text style={styles.ldName} numberOfLines={1}>
                {l.name}
              </Text>
              <CondTitle size={16} color={colors.accent}>
                {l.value}
              </CondTitle>
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    spRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', padding: 14, gap: 10 },
    spCol: { flex: 1, minWidth: 0 },
    spTeam: { color: colors.muted, fontSize: 9.5, fontFamily: fonts.bodyExtra, letterSpacing: 1.5 },
    spName: { color: colors.text, fontSize: 14, fontFamily: fonts.bodyBold },
    spLine: { color: colors.accent, fontSize: 11.5, fontFamily: fonts.condBold, letterSpacing: 0.4, marginTop: 1 },
    ldBlock: { paddingHorizontal: 14, paddingTop: 12, paddingBottom: 15 },
    ldRow: { flexDirection: 'row', gap: 10, marginTop: 8 },
    ldItem: { flex: 1, minWidth: 0 },
    ldCat: { color: colors.placeholder, fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    ldName: { color: colors.text, fontSize: 12, fontFamily: fonts.bodyBold, marginTop: 2 },
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
```

## Shared component it uses: `ScoreFlash.js`

```jsx
import { useEffect, useRef, useState } from 'react';
import { Animated } from 'react-native';
import { useTheme, fonts } from '../theme';

// A live score that celebrates its own changes: when the value ticks up it
// pops (scale spring) and flashes lime before settling back to its color.
export default function ScoreFlash({ value, size = 42, color, style }) {
  const { colors } = useTheme();
  const scale = useRef(new Animated.Value(1)).current;
  const [flash, setFlash] = useState(false);
  const prev = useRef(value);

  useEffect(() => {
    if (prev.current !== value && prev.current != null && value != null) {
      setFlash(true);
      scale.setValue(1.26);
      Animated.spring(scale, { toValue: 1, friction: 4, tension: 90, useNativeDriver: true }).start();
      const t = setTimeout(() => setFlash(false), 850);
      prev.current = value;
      return () => clearTimeout(t);
    }
    prev.current = value;
  }, [value, scale]);

  return (
    <Animated.Text
      style={[
        {
          fontFamily: fonts.hero,
          fontSize: size,
          lineHeight: size + 2,
          color: flash ? colors.accent : color || colors.text,
          paddingRight: 4,
          transform: [{ scale }],
        },
        style,
      ]}
    >
      {value ?? '—'}
    </Animated.Text>
  );
}
```

## Shared component it uses: `PlayerAvatar.js`

```jsx
import { useState } from 'react';
import { Image, View } from 'react-native';
import Avatar from './ui/Avatar';
import { useTheme } from '../theme';

// A player's face, with the initials Avatar as the fallback. Used anywhere a
// real athlete appears — draft board, rosters, live matchup, results.
//
// Falls back for two reasons: placeholder pools (NBA/NFL rows aren't seeded
// from ESPN yet, so they have no photo) and load failures. Either way the row
// looks deliberate rather than broken.
export default function PlayerAvatar({ uri, name, size = 36, style }) {
  const { colors } = useTheme();
  const [failed, setFailed] = useState(false);

  if (!uri || failed) return <Avatar name={name} size={size} style={style} />;

  return (
    <View
      style={[
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          overflow: 'hidden',
          backgroundColor: colors.cardElevated,
        },
        style,
      ]}
    >
      <Image
        source={{ uri }}
        style={{ width: size, height: size }}
        resizeMode="cover"
        onError={() => setFailed(true)}
      />
    </View>
  );
}
```
