# Scoreboard (inside the LIVE tab) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

The real slate: league chips (WNBA/MLB/NFL/NBA), day navigation, game rows — live (score + clock, red dot), final, scheduled (start time). Tap a game → game detail.

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

## The screen source (`src/screens/GamesScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { Image, ScrollView, SectionList, StyleSheet, Text, View, Pressable } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { listUpcomingGames, listGamesOn, getBoxScore } from '../api/sports';
import { teamColor, lastName } from '../utils/teamArt';
import ScoreFlash from '../components/ScoreFlash';
import { etDayISO, etTime, etWeekday } from '../time';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, EmptyState, SkeletonList, Segmented, BlinkDot, Chip, Kicker } from '../components/ui';

const WEEK = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const MON = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

const SPORTS = [
  { key: 'wnba', label: 'WNBA' },
  { key: 'mlb', label: 'MLB' },
  { key: 'nfl', label: 'NFL' },
];

// ET wall-clock via the real tz database (the old fixed -4h drifts in Nov).
function timeLabel(iso) {
  return etTime(iso);
}

// A "YYYY-MM-DD" ET day rendered as "Aug 17" (noon UTC dodges tz edges).
function isoToShort(iso) {
  const d = new Date(`${iso}T12:00:00Z`);
  return `${MON[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

// The last `n` ET calendar days, most recent first, as {iso, label}.
function pastDays(n = 7) {
  const out = [];
  for (let i = 1; i <= n; i++) {
    const iso = etDayISO(Date.now() - i * 24 * 3600 * 1000);
    out.push({ iso, label: isoToShort(iso) });
  }
  return out;
}

// Group by ET day; within a day the live games lead (hero cards), then the
// schedule, then finals. `_label` marks where the LIVE NOW / SCHEDULE / FINAL
// sub-heads render.
function buildSections(games) {
  const todayKey = etDayISO();
  const tomKey = etDayISO(Date.now() + 24 * 3600 * 1000);

  const byDay = new Map();
  for (const g of games) {
    const key = etDayISO(g.date);
    if (!byDay.has(key)) byDay.set(key, { key, first: g.date, items: [] });
    byDay.get(key).items.push(g);
  }

  return Array.from(byDay.values()).map(({ key, first, items }) => {
    let title = `${etWeekday(first).toUpperCase()} ${isoToShort(key)}`;
    if (key === todayKey) title = `TONIGHT · ${title}`;
    else if (key === tomKey) title = `TOMORROW · ${title}`;

    const rank = { in: 0, pre: 1, post: 2 };
    const ordered = [...items].sort((a, b) => (rank[a.state] ?? 1) - (rank[b.state] ?? 1));
    const hasLive = ordered.some((g) => g.state === 'in');
    const data = ordered.map((g, i) => {
      let label = null;
      if (hasLive && i === 0) label = 'live';
      else if (hasLive && ordered[i - 1]?.state === 'in' && g.state !== 'in')
        label = g.state === 'post' ? 'final' : 'schedule';
      return { ...g, _label: label };
    });
    return { title, count: data.length, data };
  });
}

export default function GamesScreen({ navigation }) {
  const { token } = useAuth();
  const { colors, scheme } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [sport, setSport] = useState('wnba');
  const [day, setDay] = useState(null); // null = the upcoming slate; 'YYYY-MM-DD' = one past day
  const [games, setGames] = useState([]);
  const [notes, setNotes] = useState({}); // gameId -> "COLLIER · 31.2 FAN PTS"
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = day ? await listGamesOn(token, sport, day) : await listUpcomingGames(token, sport);
      const list = res.games || [];
      setGames(list);
      setError(null);
      loadNotes(list);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, sport, day]);

  // The hero cards' footer line: whoever owns the best fantasy night in each
  // live game right now. A couple of extra box fetches, live games only.
  function loadNotes(list) {
    const live = list.filter((g) => g.state === 'in').slice(0, 4);
    if (live.length === 0) return setNotes({});
    Promise.all(
      live.map((g) =>
        getBoxScore(token, sport, g.id)
          .then((box) => {
            const top = (box.teams || [])
              .flatMap((t) => (t.groups || []).flatMap((gr) => gr.rows || []))
              .reduce((m, r) => (Number(r.fantasy) > Number(m?.fantasy || 0) ? r : m), null);
            return top ? [g.id, `${lastName(top.name).toUpperCase()} · ${top.fantasy} FAN PTS`] : null;
          })
          .catch(() => null)
      )
    ).then((entries) => setNotes(Object.fromEntries(entries.filter(Boolean))));
  }

  // Refresh on focus; keep polling only on the live slate — past days are done.
  useFocusEffect(
    useCallback(() => {
      load();
      if (day) return undefined;
      const iv = setInterval(load, 30000);
      return () => clearInterval(iv);
    }, [load, day])
  );

  function switchSport(next) {
    if (next === sport) return;
    setGames([]);
    setNotes({});
    setLoading(true);
    setSport(next);
  }

  function switchDay(next) {
    if (next === day) return;
    setGames([]);
    setNotes({});
    setLoading(true);
    setDay(next);
  }

  const open = (game) => navigation.navigate('GameDetail', { game, sport });

  return (
    <Screen padded={false}>
      <Segmented
        style={{ marginHorizontal: spacing.lg, marginTop: spacing.md }}
        value={sport}
        onChange={switchSport}
        options={SPORTS.map((s) => ({ key: s.key, label: s.label }))}
      />

      {/* flexShrink: 0 is load-bearing: the parent column squeezes this
          ScrollView's natural height and every chip after the first renders
          with a clipped text box (the day-strip bug). */}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, flexShrink: 0, marginTop: spacing.sm }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: spacing.lg }}>
          <Chip label="Upcoming" active={day === null} onPress={() => switchDay(null)} />
          {pastDays().map((d) => (
            <Chip key={d.iso} label={d.label} active={day === d.iso} onPress={() => switchDay(d.iso)} />
          ))}
        </View>
      </ScrollView>

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
            ) : day ? (
              <EmptyState icon="moon-outline" title="Quiet night" subtitle="No games on that date — pick another day." />
            ) : (
              <EmptyState icon="calendar-outline" title="No upcoming games" subtitle="Check back when the next slate is scheduled." />
            )
          }
          renderSectionHeader={({ section }) => (
            <View style={styles.dayHead}>
              <Text style={styles.dayHeadText}>
                {section.title} · {section.count} {section.count === 1 ? 'GAME' : 'GAMES'}
              </Text>
              <View style={styles.dayHeadRule} />
            </View>
          )}
          renderItem={({ item }) => (
            <>
              {item._label === 'live' ? (
                <View style={styles.subHead}>
                  <BlinkDot color={colors.danger} size={6} period={1100} />
                  <Text style={[styles.subHeadText, { color: colors.danger }]}>LIVE NOW</Text>
                </View>
              ) : null}
              {item._label === 'schedule' || item._label === 'final' ? (
                <Text style={[styles.subHeadText, { marginTop: spacing.md, marginBottom: 2 }]}>
                  {item._label === 'final' ? 'FINAL' : 'SCHEDULE'}
                </Text>
              ) : null}
              {item.state === 'in' ? (
                <HeroLiveCard game={item} note={notes[item.id]} onPress={() => open(item)} styles={styles} colors={colors} scheme={scheme} />
              ) : (
                <GameRow game={item} onPress={() => open(item)} styles={styles} colors={colors} />
              )}
            </>
          )}
        />
      )}
    </Screen>
  );
}

// A live game gets the full hero treatment: real logos with team-color glows,
// ghost crests in the corners, flashing scores, and a momentum bar.
function HeroLiveCard({ game, note, onPress, styles, colors, scheme }) {
  const aC = teamColor(game.away);
  const hC = teamColor(game.home);
  const a = Number(game.away.score) || 0;
  const h = Number(game.home.score) || 0;
  const tot = a + h;
  const pctA = tot ? Math.round((a / tot) * 100) : 50;
  const ghost = scheme === 'dark' ? 0.09 : 0.05;
  const lead = a === h ? 'TIED' : `${a > h ? game.away.abbrev : game.home.abbrev} BY ${Math.abs(a - h)}`;

  return (
    <Pressable onPress={onPress} style={({ pressed }) => [pressed && { transform: [{ scale: 0.985 }] }]}>
      <LinearGradient
        colors={[withAlpha(aC, 0.2), colors.card, withAlpha(hC, 0.2)]}
        locations={[0, 0.5, 1]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={styles.hero}
      >
        {game.away.logo ? <Image source={{ uri: game.away.logo }} style={[styles.heroGhostA, { opacity: ghost }]} /> : null}
        {game.home.logo ? <Image source={{ uri: game.home.logo }} style={[styles.heroGhostH, { opacity: ghost }]} /> : null}

        <View style={styles.heroGrid}>
          <TeamCol side={game.away} big styles={styles} />
          <View style={styles.heroCenter}>
            <ScoreFlash value={game.away.score} size={40} color={a >= h ? colors.accent : colors.text} />
            <View style={styles.heroMid}>
              <View style={styles.liveTag}>
                <BlinkDot color={colors.danger} size={5} period={1100} />
                <Text style={styles.liveTagText}>LIVE</Text>
              </View>
              <Text style={styles.heroClock} numberOfLines={2}>
                {game.status}
              </Text>
            </View>
            <ScoreFlash value={game.home.score} size={40} color={h >= a ? colors.accent : colors.text} />
          </View>
          <TeamCol side={game.home} big styles={styles} />
        </View>

        <View style={styles.momTrack}>
          <View style={{ width: `${pctA}%`, backgroundColor: aC }} />
          <View style={{ flex: 1, backgroundColor: hC }} />
        </View>

        <View style={styles.heroFoot}>
          <Text style={styles.heroNote} numberOfLines={1}>
            {note || 'Real game · fantasy scoring live'}
          </Text>
          <Text style={styles.heroLead}>{lead}</Text>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

function TeamCol({ side, big, styles }) {
  const c = teamColor(side);
  const size = big ? 48 : 40;
  return (
    <View style={styles.teamCol}>
      {side.logo ? (
        <Image
          source={{ uri: side.logo }}
          style={{ width: size, height: size, shadowColor: c, shadowOpacity: 0.5, shadowRadius: 8, shadowOffset: { width: 0, height: 4 } }}
        />
      ) : null}
      <Text style={styles.teamColCode}>{side.abbrev}</Text>
      <Text style={styles.teamColName} numberOfLines={1}>
        {String(side.name || '').toUpperCase()}
      </Text>
    </View>
  );
}

// Scheduled + final games: a compact two-line row, tinted by the team colors.
function GameRow({ game, onPress, styles, colors }) {
  const pre = game.state === 'pre';
  const a = Number(game.away.score);
  const h = Number(game.home.score);
  const aC = teamColor(game.away);
  const hC = teamColor(game.home);

  const line = (side, mine, other) => (
    <View style={styles.rowLine}>
      {side.logo ? <Image source={{ uri: side.logo }} style={{ width: 26, height: 26 }} /> : <View style={{ width: 26 }} />}
      <Text style={styles.rowCode}>{side.abbrev}</Text>
      <Text style={styles.rowName} numberOfLines={1}>
        {side.name}
      </Text>
      {!pre ? (
        <Text style={[styles.rowScore, { color: mine > other ? colors.accent : colors.muted }]}>{side.score}</Text>
      ) : null}
    </View>
  );

  return (
    <Pressable onPress={onPress} style={({ pressed }) => [pressed && { transform: [{ scale: 0.985 }] }]}>
      <LinearGradient
        colors={[withAlpha(aC, 0.1), colors.card, withAlpha(hC, 0.1)]}
        locations={[0, 0.5, 1]}
        start={{ x: 0, y: 0 }}
        end={{ x: 0, y: 1 }}
        style={styles.row}
      >
        <View style={{ flex: 1, gap: 8, paddingVertical: 11, paddingLeft: 12 }}>
          {line(game.away, a, h)}
          {line(game.home, h, a)}
        </View>
        <View style={styles.rowRight}>
          <Text style={[styles.rowStTop, { color: pre ? colors.accent : colors.muted }]}>
            {pre ? timeLabel(game.date) : 'FINAL'}
          </Text>
          <Text style={styles.rowStSub}>{pre ? 'ET' : ''}</Text>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    dayHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: spacing.lg, marginBottom: 2 },
    dayHeadText: { color: colors.placeholder, fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 2 },
    dayHeadRule: { flex: 1, height: StyleSheet.hairlineWidth, backgroundColor: colors.border },
    subHead: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: spacing.md, marginBottom: 2 },
    subHeadText: { color: colors.placeholder, fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 2 },

    // live hero
    hero: {
      borderRadius: 18,
      borderWidth: 1,
      borderColor: colors.border,
      overflow: 'hidden',
      padding: 14,
      paddingBottom: 12,
      marginTop: spacing.sm,
    },
    heroGhostA: { position: 'absolute', left: -34, top: -30, width: 150, height: 150 },
    heroGhostH: { position: 'absolute', right: -34, bottom: -38, width: 150, height: 150 },
    heroGrid: { flexDirection: 'row', alignItems: 'center' },
    heroCenter: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 },
    heroMid: { alignItems: 'center', gap: 2, minWidth: 52, maxWidth: 74 },
    liveTag: { flexDirection: 'row', alignItems: 'center', gap: 4 },
    liveTagText: { color: colors.danger, fontSize: 7.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5 },
    heroClock: { color: colors.muted, fontSize: 10, fontFamily: fonts.condBold, textAlign: 'center' },
    teamCol: { alignItems: 'center', gap: 2, width: 74 },
    teamColCode: { color: colors.text, fontFamily: fonts.hero, fontSize: 16, marginTop: 4, paddingRight: 2 },
    teamColName: { color: colors.muted, fontSize: 8.5, fontFamily: fonts.bodyExtra, letterSpacing: 1, maxWidth: 72 },
    momTrack: { flexDirection: 'row', height: 4, borderRadius: 2, overflow: 'hidden', marginTop: 12, backgroundColor: colors.border },
    heroFoot: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 8, gap: 8 },
    heroNote: { flex: 1, color: colors.muted, fontSize: 9.5, fontFamily: fonts.bodyBold, letterSpacing: 0.5 },
    heroLead: { color: colors.accent, fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },

    // schedule / final rows
    row: {
      flexDirection: 'row',
      borderRadius: 14,
      borderWidth: 1,
      borderColor: colors.border,
      overflow: 'hidden',
      marginTop: spacing.sm,
    },
    rowLine: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingRight: 12 },
    rowCode: { color: colors.text, fontFamily: fonts.hero, fontSize: 15, width: 44 },
    rowName: { flex: 1, color: colors.muted, fontSize: 11.5, fontFamily: fonts.bodySemi },
    rowScore: { fontFamily: fonts.hero, fontSize: 20, lineHeight: 22, paddingRight: 2 },
    rowRight: {
      width: 66,
      borderLeftColor: colors.borderSubtle,
      borderLeftWidth: StyleSheet.hairlineWidth,
      alignItems: 'center',
      justifyContent: 'center',
      gap: 2,
    },
    rowStTop: { fontFamily: fonts.condBold, fontSize: 13, letterSpacing: 0.5 },
    rowStSub: { color: colors.placeholder, fontSize: 8.5, fontFamily: fonts.bodyExtra, letterSpacing: 0.5, height: 11 },
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
