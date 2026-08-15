# Friend requests — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Incoming requests — accept or decline.

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

## The screen source (`src/screens/RequestsScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listRequests, acceptRequest, deleteRequest } from '../api/social';
import { notify, NotifyType } from '../haptics';
import { useThemedStyles, spacing, font } from '../theme';
import { Screen, Avatar, Button, EmptyState, SkeletonList } from '../components/ui';

export default function RequestsScreen() {
  const { token } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await listRequests(token);
      setRequests(res.requests);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  async function respond(request, action) {
    notify(action === 'accept' ? NotifyType.Success : NotifyType.Warning);
    setRequests((prev) => prev.filter((r) => r.id !== request.id));
    try {
      if (action === 'accept') {
        await acceptRequest(token, request.id);
      } else {
        await deleteRequest(token, request.id);
      }
    } catch (e) {
      setError(e.message);
      load();
    }
  }

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <SkeletonList count={4} />
        ) : (
          <FlatList
            data={requests}
            keyExtractor={(item) => String(item.id)}
            ItemSeparatorComponent={() => <View style={styles.sep} />}
            contentContainerStyle={requests.length === 0 && { flexGrow: 1, justifyContent: 'center' }}
            ListEmptyComponent={
              <EmptyState icon="mail-open-outline" title="No pending requests" subtitle="When someone wants to add you, it'll show up here." />
            }
            renderItem={({ item }) => (
              <View style={styles.row}>
                <Avatar name={item.user.username} size={44} />
                <Text style={styles.username}>{item.user.username}</Text>
                <View style={styles.buttons}>
                  <Button title="Accept" size="sm" full={false} icon="checkmark" onPress={() => respond(item, 'accept')} />
                  <Button title="Decline" size="sm" variant="outline" full={false} haptic={false} onPress={() => respond(item, 'decline')} />
                </View>
              </View>
            )}
          />
        )}
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
    buttons: { flexDirection: 'row', gap: spacing.sm },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.sm },
  });
```
