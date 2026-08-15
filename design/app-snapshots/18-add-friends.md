# Add friends (search) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Find a user by username fragment, send the request, see sent/already-crew states.

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

## The screen source (`src/screens/SearchScreen.js`)

```jsx
import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { searchUsers, sendFriendRequest } from '../api/social';
import { useTheme, useThemedStyles, spacing, font } from '../theme';
import { Screen, Avatar, Button, Badge, EmptyState, SearchInput } from '../components/ui';

export default function SearchScreen() {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < 2) {
      setResults([]);
      return;
    }

    let cancelled = false;
    setLoading(true);
    const timer = setTimeout(async () => {
      try {
        const res = await searchUsers(token, trimmed);
        if (!cancelled) setResults(res.users);
      } catch (e) {
        if (!cancelled) setError(e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 300);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query, token]);

  async function add(user) {
    setResults((prev) => prev.map((u) => (u.id === user.id ? { ...u, relationship: 'request_sent' } : u)));
    try {
      await sendFriendRequest(token, user.id);
    } catch (e) {
      setError(e.message);
      setResults((prev) => prev.map((u) => (u.id === user.id ? { ...u, relationship: 'none' } : u)));
    }
  }

  function renderAction(user) {
    switch (user.relationship) {
      case 'friends':
        return <Badge label="Friends" tone="accent" />;
      case 'request_sent':
        return <Badge label="Requested" tone="info" />;
      case 'request_received':
        return <Badge label="Wants to add you" tone="warning" />;
      default:
        return <Button title="Add" size="sm" full={false} icon="person-add" onPress={() => add(user)} />;
    }
  }

  const trimmed = query.trim();

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <SearchInput value={query} onChangeText={setQuery} placeholder="Search by username" autoFocus />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <FlatList
          data={results}
          keyExtractor={(item) => String(item.id)}
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={{ paddingTop: spacing.sm, flexGrow: 1 }}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          ListHeaderComponent={loading ? <ActivityIndicator color={colors.muted} style={{ marginVertical: spacing.md }} /> : null}
          ListEmptyComponent={
            trimmed.length >= 2 && !loading ? (
              <EmptyState icon="search" title="No users found" subtitle="Double-check the spelling and try again." />
            ) : trimmed.length === 1 ? (
              <EmptyState icon="text-outline" title="Keep typing" subtitle="Enter at least 2 letters to search." />
            ) : (
              <EmptyState icon="person-add-outline" title="Find your friends" subtitle="Search by username to send a friend request." />
            )
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Avatar name={item.username} size={44} />
              <Text style={styles.username}>{item.username}</Text>
              {renderAction(item)}
            </View>
          )}
        />
      </View>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
    username: { color: colors.text, fontSize: font.subtitle, fontWeight: '600', marginLeft: spacing.md, flex: 1 },
    error: { color: colors.danger, textAlign: 'center', marginVertical: spacing.sm },
  });
```
