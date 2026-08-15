# Friend standings — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Your friends ranked by record — the bragging table.

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

## The screen source (`src/screens/LeaderboardScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getLeaderboard } from '../api/me';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList } from '../components/ui';

const MEDAL = { 1: '🥇', 2: '🥈', 3: '🥉' };

export default function LeaderboardScreen() {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [rows, setRows] = useState(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      getLeaderboard(token)
        .then((r) => active && setRows(r.leaderboard || []))
        .catch(() => active && setRows([]));
      return () => {
        active = false;
      };
    }, [token])
  );

  if (rows === null) {
    return (
      <Screen>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  return (
    <Screen padded={false}>
      <FlatList
        data={rows}
        keyExtractor={(item) => String(item.user.id)}
        contentContainerStyle={{ padding: spacing.lg }}
        ListHeaderComponent={<Text style={styles.intro}>Standings among you and your friends, by wins.</Text>}
        ListEmptyComponent={<EmptyState icon="podium-outline" title="The podium is empty" subtitle="Win a duel and plant your flag at #1." />}
        renderItem={({ item }) => {
          const me = item.user.id === user?.id;
          return (
            <View style={[styles.row, me && styles.meRow]}>
              <Text style={styles.rank}>{MEDAL[item.rank] || item.rank}</Text>
              <Avatar name={item.user.username} size={36} />
              <View style={{ flex: 1, marginLeft: spacing.md }}>
                <Text style={[styles.name, me && { color: colors.accent }]}>
                  {item.user.username}
                  {me ? ' (you)' : ''}
                </Text>
                <Text style={styles.sub}>
                  {item.played} played · {Math.round((item.win_pct || 0) * 100)}% win
                </Text>
              </View>
              <Text style={styles.record}>
                {item.wins}-{item.losses}
                {item.ties ? `-${item.ties}` : ''}
              </Text>
            </View>
          );
        }}
      />
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, marginBottom: spacing.md },
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      borderRadius: radius.md,
      padding: spacing.md,
      marginBottom: spacing.sm,
    },
    meRow: { borderColor: colors.accentBorder },
    rank: { color: colors.text, fontSize: 17, fontFamily: fonts.hero, width: 30, textAlign: 'center', marginRight: spacing.sm },
    name: { color: colors.text, fontSize: font.subtitle, fontWeight: '700' },
    sub: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    record: { color: colors.text, fontSize: 17, fontFamily: fonts.heroUpright },
  });
```
