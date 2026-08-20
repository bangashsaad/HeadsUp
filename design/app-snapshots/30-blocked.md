# Blocked players — settings sub-screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Current + new password form.

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

## The screen source (`src/screens/BlockedScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listBlocked, unblockUser } from '../api/social';
import { useTheme, useThemedStyles, spacing, font, fonts } from '../theme';
import { Screen, Card, Avatar, EmptyState, SkeletonList } from '../components/ui';

// Everyone you've blocked, with the way back out. Unblocking does NOT restore
// the friendship — you can re-add each other if you both want to.
export default function BlockedScreen() {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [blocked, setBlocked] = useState(null);
  const [error, setError] = useState(null);
  const [busyId, setBusyId] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listBlocked(token);
      setBlocked(res.blocked || res.users || []);
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  async function unblock(u) {
    setBusyId(u.id);
    try {
      await unblockUser(token, u.id);
      setBlocked((cur) => (cur || []).filter((x) => x.id !== u.id));
    } catch (e) {
      Alert.alert("Couldn't unblock", e.message);
    } finally {
      setBusyId(null);
    }
  }

  if (error) {
    return (
      <Screen>
        <EmptyState icon="alert-circle-outline" title="Couldn't load the list" subtitle={error} />
      </Screen>
    );
  }

  if (blocked == null) {
    return (
      <Screen>
        <SkeletonList count={4} />
      </Screen>
    );
  }

  if (blocked.length === 0) {
    return (
      <Screen>
        <EmptyState
          icon="shield-checkmark-outline"
          title="Nobody's blocked"
          subtitle="Block someone from their rivalry page — it cancels shared duels, refunds stakes, and they can't reach you."
        />
      </Screen>
    );
  }

  return (
    <Screen scroll>
      <Card padded={false}>
        {blocked.map((u, i) => (
          <View key={u.id} style={[styles.row, i > 0 && styles.divider]}>
            <Avatar name={u.username} size={36} />
            <Text style={styles.name} numberOfLines={1}>
              {u.username}
            </Text>
            <Pressable
              onPress={() => unblock(u)}
              disabled={busyId === u.id}
              style={({ pressed }) => [styles.unblockBtn, (pressed || busyId === u.id) && { opacity: 0.6 }]}
            >
              <Text style={styles.unblockText}>{busyId === u.id ? '…' : 'UNBLOCK'}</Text>
            </Pressable>
          </View>
        ))}
      </Card>
      <Text style={styles.note}>Unblocking doesn't restore the friendship — you can re-add each other after.</Text>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    divider: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    name: { flex: 1, color: colors.text, fontSize: font.bodyLg, fontFamily: fonts.bodyBold },
    unblockBtn: { borderWidth: 1, borderColor: colors.border, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 7 },
    unblockText: { color: colors.muted, fontSize: 10.5, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
    note: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.lg, lineHeight: 18, fontFamily: fonts.body },
  });
```
