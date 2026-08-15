# Player profile — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

One athlete: headshot, team/position, injury status, FPG projection, next game, recent game log with fantasy points.

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

## The screen source (`src/screens/PlayerProfileScreen.js`)

```jsx
import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { getPlayerProfile } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Card, Avatar, Badge, EmptyState, SkeletonList } from '../components/ui';
import PlayerAvatar from '../components/PlayerAvatar';
import InjuryBadge from '../components/InjuryBadge';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function shortDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

export default function PlayerProfileScreen({ route }) {
  const { id, name, team, position } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await getPlayerProfile(token, id);
        if (active) setProfile(res);
      } catch (e) {
        if (active) setError(e.message);
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [token, id]);

  const header = (
    <View style={styles.header}>
      <PlayerAvatar
        uri={profile?.player?.headshot_url}
        name={name || profile?.player?.name || '?'}
        size={64}
      />
      <InjuryBadge injury={profile?.player?.injury} style={{ marginTop: 8 }} />
      <View style={{ marginLeft: spacing.lg, flex: 1 }}>
        <Text style={styles.name}>{name || profile?.player?.name}</Text>
        <Text style={styles.sub}>
          {(team || profile?.player?.team) ?? ''} · {(position || profile?.player?.position) ?? ''}
        </Text>
      </View>
    </View>
  );

  if (loading) {
    return (
      <Screen>
        {header}
        <SkeletonList count={6} />
      </Screen>
    );
  }

  if (error) {
    return (
      <Screen>
        {header}
        <EmptyState icon="alert-circle-outline" title="Couldn't load stats" subtitle={error} />
      </Screen>
    );
  }

  if (!profile?.available) {
    return (
      <Screen>
        {header}
        <EmptyState
          icon="stats-chart-outline"
          title="Stats coming soon"
          subtitle="Live stats are available for WNBA and MLB players right now. Other leagues are on the way."
        />
      </Screen>
    );
  }

  const s = profile.season || {};
  const tiles = s.tiles || [];

  return (
    <Screen scroll>
      {header}

      <Card style={styles.avgCard}>
        <View style={styles.avgGrid}>
          {tiles.map((t) => (
            <Stat key={t.label} label={t.label} value={t.value} accent={t.label === 'FPG'} styles={styles} />
          ))}
        </View>
        <Text style={styles.avgNote}>Season totals & averages over {s.games_played ?? 0} games</Text>
      </Card>

      <Text style={styles.logTitle}>Game log</Text>
      {(profile.games || []).length === 0 ? (
        <EmptyState icon="calendar-outline" title="No games yet" subtitle="This player hasn't logged a game this season." />
      ) : (
        <Card padded={false}>
          {profile.games.map((g, i) => (
            <View key={g.event_id} style={[styles.gameRow, i < profile.games.length - 1 && styles.gameDivider]}>
              <View style={{ flex: 1 }}>
                <View style={styles.gameTop}>
                  <Text style={styles.gameDate}>{shortDate(g.date)}</Text>
                  <Text style={styles.gameMatch}>
                    {g.home_away === '@' ? '@' : 'vs'} {g.opponent}
                  </Text>
                  {g.result ? (
                    <Badge label={g.result} tone={g.result === 'W' ? 'accent' : 'danger'} />
                  ) : null}
                </View>
                <Text style={styles.gameBox}>{g.line}</Text>
              </View>
              <View style={styles.fanWrap}>
                <Text style={styles.fanValue}>{g.fantasy}</Text>
                <Text style={styles.fanLabel}>FAN</Text>
              </View>
            </View>
          ))}
        </Card>
      )}
    </Screen>
  );
}

function Stat({ label, value, accent, styles }) {
  return (
    <View style={styles.stat}>
      <Text style={[styles.statValue, accent && styles.statAccent]}>{value ?? '—'}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg },
    name: { color: colors.text, fontSize: 26, fontFamily: fonts.hero, paddingRight: 4 },
    sub: { color: colors.muted, fontSize: font.body, marginTop: 2 },
    avgCard: { marginBottom: spacing.lg },
    avgGrid: { flexDirection: 'row', justifyContent: 'space-between' },
    stat: { alignItems: 'center', flex: 1 },
    statValue: { color: colors.text, fontSize: 24, fontFamily: fonts.hero },
    statAccent: { color: colors.accent },
    statLabel: { color: colors.muted, fontSize: 10, fontWeight: '700', letterSpacing: 0.5, marginTop: 2 },
    avgNote: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.md },
    logTitle: { color: colors.text, fontSize: font.bodyLg, fontWeight: '700', marginBottom: spacing.sm },
    gameRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: spacing.lg },
    gameDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    gameTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    gameDate: { color: colors.muted, fontSize: font.small, fontWeight: '700', width: 48 },
    gameMatch: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    gameBox: { color: colors.muted, fontSize: font.caption, marginTop: 4 },
    fanWrap: { alignItems: 'center', marginLeft: spacing.md },
    fanValue: { color: colors.accent, fontSize: 19, fontFamily: fonts.hero },
    fanLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
  });
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

## Shared component it uses: `InjuryBadge.js`

```jsx
import { StyleSheet, Text, View } from 'react-native';
import { useTheme, fonts, withAlpha } from '../theme';

// OUT / IL-60 / GTD. Red means "will not play" — a guaranteed zero on a
// single-day slate. Amber means "might play".
//
// Renders nothing when there's no injury, so callers can drop it in
// unconditionally without a ternary at every call site.
export default function InjuryBadge({ injury, style }) {
  const { colors } = useTheme();
  if (!injury?.label) return null;

  const out = injury.status === 'out';
  const tint = out ? colors.danger : colors.gold;

  return (
    <View
      style={[
        styles.badge,
        { backgroundColor: withAlpha(tint, 0.15), borderColor: withAlpha(tint, 0.45) },
        style,
      ]}
    >
      <Text style={[styles.text, { color: tint }]}>{injury.label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: { paddingHorizontal: 5, paddingVertical: 1, borderRadius: 4, borderWidth: 1 },
  text: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
});
```
