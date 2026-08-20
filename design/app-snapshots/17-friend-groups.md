# Friend groups — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Private crews as tabs (e.g. HOOPS CREW): create a group, add members, see the group's members. (The coming clan-chat build lives here.)

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

## The screen source (`src/screens/FriendGroupsScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import {
  listFriends,
  listFriendGroups,
  createFriendGroup,
  renameFriendGroup,
  deleteFriendGroup,
  setFriendGroupMembers,
} from '../api/social';
import { selection, impact, ImpactStyle } from '../haptics';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, Button, EmptyState, SkeletonList } from '../components/ui';

const NAME_MAX = 20;

// Private buckets of friends ("COLLEGE", "WORK") that become the recipient tabs
// on the challenge screen. Nobody sees the group they're in.
export default function FriendGroupsScreen() {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [friends, setFriends] = useState([]);
  const [groups, setGroups] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null); // group being edited
  const [naming, setNaming] = useState(false);
  const [draftName, setDraftName] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [f, g] = await Promise.all([listFriends(token), listFriendGroups(token)]);
      setFriends(f.friends || []);
      setGroups(g.groups || []);
      setError(null);
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

  async function submitName() {
    const name = draftName.trim();
    if (!name) return;
    setBusy(true);
    try {
      if (naming === 'new') await createFriendGroup(token, name);
      else await renameFriendGroup(token, naming.id, name);
      setNaming(false);
      setDraftName('');
      await load();
    } catch (e) {
      Alert.alert("Couldn't save", e.message);
    } finally {
      setBusy(false);
    }
  }

  function confirmDelete(group) {
    Alert.alert(`Delete ${group.name}?`, 'The group goes away. Your friendships are untouched.', [
      { text: 'Keep', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteFriendGroup(token, group.id);
            await load();
          } catch (e) {
            Alert.alert("Couldn't delete", e.message);
          }
        },
      },
    ]);
  }

  async function toggleMember(group, friendId) {
    const current = group.member_ids || [];
    const next = current.includes(friendId) ? current.filter((x) => x !== friendId) : [...current, friendId];
    impact(ImpactStyle.Light);
    // Optimistic — the server replaces membership wholesale.
    setEditing({ ...group, member_ids: next });
    setGroups((gs) => gs.map((g) => (g.id === group.id ? { ...g, member_ids: next } : g)));
    try {
      await setFriendGroupMembers(token, group.id, next);
    } catch (e) {
      Alert.alert("Couldn't update", e.message);
      load();
    }
  }

  if (loading) {
    return (
      <Screen>
        <SkeletonList count={5} />
      </Screen>
    );
  }

  return (
    <Screen scroll>
      <Text style={styles.intro}>
        Groups are private shortcuts for challenging people — nobody knows which group they're in. A friend can be in
        several.
      </Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      {friends.length === 0 ? (
        <EmptyState icon="people-outline" title="No friends yet" subtitle="Add friends first — then you can group them." />
      ) : (
        <>
          {groups.map((g) => (
            <View key={g.id} style={styles.card}>
              <Pressable
                onPress={() => {
                  selection();
                  setEditing(editing?.id === g.id ? null : g);
                }}
                style={styles.cardHead}
              >
                <Text style={styles.groupName}>{g.name.toUpperCase()}</Text>
                <Text style={styles.groupCount}>{(g.member_ids || []).length}</Text>
                <Ionicons
                  name={editing?.id === g.id ? 'chevron-up' : 'chevron-down'}
                  size={17}
                  color={colors.placeholder}
                />
              </Pressable>

              {editing?.id === g.id ? (
                <View>
                  {friends.map((f, i) => {
                    const inGroup = (editing.member_ids || []).includes(f.id);
                    return (
                      <Pressable
                        key={f.id}
                        onPress={() => toggleMember(editing, f.id)}
                        style={({ pressed }) => [
                          styles.person,
                          i < friends.length - 1 && styles.divider,
                          pressed && { backgroundColor: colors.cardElevated },
                        ]}
                      >
                        <Avatar name={f.username} size={34} />
                        <Text style={styles.personName} numberOfLines={1}>
                          {f.username}
                        </Text>
                        <Ionicons
                          name={inGroup ? 'checkmark-circle' : 'ellipse-outline'}
                          size={21}
                          color={inGroup ? colors.accent : colors.placeholder}
                        />
                      </Pressable>
                    );
                  })}
                  <View style={styles.cardActions}>
                    <Pressable
                      onPress={() => {
                        setNaming(g);
                        setDraftName(g.name);
                      }}
                      hitSlop={8}
                    >
                      <Text style={styles.linkBtn}>Rename</Text>
                    </Pressable>
                    <Pressable onPress={() => confirmDelete(g)} hitSlop={8}>
                      <Text style={[styles.linkBtn, { color: colors.danger }]}>Delete</Text>
                    </Pressable>
                  </View>
                </View>
              ) : null}
            </View>
          ))}

          <Button
            title="New group"
            icon="add"
            variant="outline"
            onPress={() => {
              setNaming('new');
              setDraftName('');
            }}
            style={{ marginTop: spacing.md }}
          />
        </>
      )}

      <Modal visible={!!naming} transparent animationType="fade" onRequestClose={() => setNaming(false)}>
        <Pressable style={styles.backdrop} onPress={() => setNaming(false)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <Text style={styles.sheetTitle}>{naming === 'new' ? 'NEW GROUP' : 'RENAME GROUP'}</Text>
            <TextInput
              value={draftName}
              onChangeText={(t) => setDraftName(t.slice(0, NAME_MAX))}
              placeholder="College"
              placeholderTextColor={colors.placeholder}
              style={styles.input}
              autoFocus
              autoCapitalize="words"
              onSubmitEditing={submitName}
            />
            <Text style={styles.hint}>
              {draftName.trim().length}/{NAME_MAX}
            </Text>
            <Button title="Save" onPress={submitName} loading={busy} disabled={!draftName.trim()} style={{ marginTop: spacing.sm }} />
          </Pressable>
        </Pressable>
      </Modal>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: 13, lineHeight: 19, marginBottom: spacing.lg, fontFamily: fonts.body },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.sm },
    card: {
      backgroundColor: colors.card,
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      overflow: 'hidden',
      marginBottom: spacing.sm,
    },
    cardHead: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 14, paddingVertical: 14 },
    groupName: { flex: 1, color: colors.text, fontSize: 14, fontFamily: fonts.heroUpright, letterSpacing: 1.5 },
    groupCount: { color: colors.accent, fontSize: 13, fontFamily: fonts.bodyBlack },
    divider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.borderSubtle },
    person: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 14, paddingVertical: 9, minHeight: 52 },
    personName: { flex: 1, color: colors.text, fontSize: 14, fontFamily: fonts.bodyBold },
    cardActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.lg, padding: 14 },
    linkBtn: { color: colors.accent, fontSize: 13, fontFamily: fonts.bodyBold },

    backdrop: { flex: 1, backgroundColor: withAlpha('#000000', 0.65), justifyContent: 'center', padding: spacing.lg },
    sheet: { backgroundColor: colors.card, borderRadius: 18, borderWidth: 1, borderColor: colors.border, padding: spacing.lg },
    sheetTitle: { color: colors.text, fontSize: 15, fontFamily: fonts.heroUpright, letterSpacing: 1.5, marginBottom: spacing.md },
    input: {
      color: colors.text,
      fontSize: 18,
      fontFamily: fonts.bodyBold,
      paddingVertical: 12,
      paddingHorizontal: 14,
      borderRadius: 13,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
    },
    hint: { color: colors.placeholder, fontSize: 11, textAlign: 'right', marginTop: 5, fontFamily: fonts.body },
  });
```
