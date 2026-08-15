# Friends list — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

The crew: friends with records and head-to-head, tap → rival profile, plus paths to add/search and requests.

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

## The screen source (`src/screens/FriendsScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { FlatList, RefreshControl, StyleSheet, Text, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listFriends, listRequests } from '../api/social';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Avatar, Button, EmptyState, SkeletonList } from '../components/ui';

export default function FriendsScreen({ navigation }) {
  const { token, signOut } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [friends, setFriends] = useState([]);
  const [requestCount, setRequestCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [friendsRes, requestsRes] = await Promise.all([listFriends(token), listRequests(token)]);
      setFriends(friendsRes.friends);
      setRequestCount(requestsRes.requests.length);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function onRefresh() {
    setRefreshing(true);
    load();
  }

  function ActionTile({ icon, label, onPress, count = 0 }) {
    return (
      <Pressable onPress={onPress} style={({ pressed }) => [styles.tile, pressed && { opacity: 0.85, transform: [{ scale: 0.99 }] }]}>
        <Ionicons name={icon} size={20} color={colors.accent} />
        <Text style={styles.tileText}>{label}</Text>
        {count > 0 ? (
          <View style={styles.countBadge}>
            <Text style={styles.countText}>{count}</Text>
          </View>
        ) : null}
      </Pressable>
    );
  }

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <View style={styles.actions}>
          <ActionTile icon="person-add" label="Add friends" onPress={() => navigation.navigate('Search')} />
          <ActionTile icon="mail" label="Requests" count={requestCount} onPress={() => navigation.navigate('Requests')} />
        </View>

        <View style={styles.actions}>
          <ActionTile icon="albums" label="Groups" onPress={() => navigation.navigate('FriendGroups')} />
        </View>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <SkeletonList count={6} />
        ) : (
          <FlatList
            data={friends}
            keyExtractor={(item) => String(item.id)}
            refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.muted} />}
            ItemSeparatorComponent={() => <View style={styles.sep} />}
            contentContainerStyle={friends.length === 0 && { flexGrow: 1, justifyContent: 'center' }}
            ListEmptyComponent={
              <EmptyState
                icon="people-outline"
                title="No friends yet"
                subtitle="Add your buddies to start challenging them head-to-head."
                action={<Button title="Add friends" icon="person-add" onPress={() => navigation.navigate('Search')} />}
              />
            }
            renderItem={({ item }) => (
              <View style={styles.row}>
                <Avatar name={item.username} size={44} />
                <Text style={styles.username}>{item.username}</Text>
              </View>
            )}
          />
        )}
      </View>

      <View style={styles.footer}>
        <Button title="Log Out" variant="danger" icon="log-out-outline" onPress={signOut} />
      </View>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    actions: { flexDirection: 'row', gap: spacing.md, marginBottom: spacing.md },
    tile: {
      flex: 1,
      flexDirection: 'row',
      justifyContent: 'center',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: radius.md,
      paddingVertical: 14,
    },
    tileText: { color: colors.text, fontSize: font.body, fontWeight: '700', marginLeft: 8 },
    countBadge: { marginLeft: 8, backgroundColor: colors.accent, borderRadius: 10, minWidth: 20, paddingHorizontal: 6, paddingVertical: 1, alignItems: 'center' },
    countText: { color: colors.onAccent, fontSize: font.caption, fontWeight: '800' },
    sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
    username: { color: colors.text, fontSize: font.subtitle, fontWeight: '600', marginLeft: spacing.md },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.sm },
    footer: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
  });
```
