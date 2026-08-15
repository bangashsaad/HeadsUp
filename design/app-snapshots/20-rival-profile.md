# Rival profile — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Another user: their record, your head-to-head ledger vs them (last duels, swings), and CHALLENGE THEM.

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

## The screen source (`src/screens/UserProfileScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { Alert, ActivityIndicator, StyleSheet, Text, View, Pressable } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getUserProfile, sendFriendRequest, acceptRequest, blockUser } from '../api/social';
import { notify, NotifyType } from '../haptics';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Card, Avatar, Badge, Button, EmptyState } from '../components/ui';

// Another player's profile, reachable by tapping them anywhere in a game
// (challenge seats, live standings, results). Shows their record, your
// head-to-head, and the friend action — how you add someone you just met
// in a group duel.
export default function UserProfileScreen({ route, navigation }) {
  const { id, username: usernameParam } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [profile, setProfile] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      (async () => {
        try {
          const res = await getUserProfile(token, id);
          if (active) setProfile(res.profile);
        } catch (e) {
          if (active) setError(e.message);
        }
      })();
      return () => {
        active = false;
      };
    }, [token, id])
  );

  function confirmBlock() {
    Alert.alert(
      `Block ${profile.user.username}?`,
      "They won't be able to find you, add you, or challenge you — and you won't see them either. Any friendship between you ends. They are not told.",
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Block',
          style: 'destructive',
          onPress: async () => {
            try {
              await blockUser(token, profile.user.id);
              navigation.goBack();
            } catch (e) {
              Alert.alert("Couldn't block", e.message);
            }
          },
        },
      ]
    );
  }

  async function addFriend() {
    setBusy(true);
    setError(null);
    try {
      await sendFriendRequest(token, id);
      notify(NotifyType.Success);
      setProfile((p) => ({ ...p, relationship: 'request_sent' }));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function acceptFriend() {
    setBusy(true);
    setError(null);
    try {
      await acceptRequest(token, profile.friendship_id);
      notify(NotifyType.Success);
      setProfile((p) => ({ ...p, relationship: 'friends' }));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  if (error && !profile) {
    return (
      <Screen>
        <EmptyState icon="alert-circle-outline" title="Couldn't load this profile" subtitle={error} />
      </Screen>
    );
  }

  if (!profile) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  const name = profile.user.username || usernameParam;
  const r = profile.record;
  const vs = profile.vs_you;
  const history = profile.history || [];

  // Jumps to the challenge form with this player already picked. Goes through
  // the Duels tab because the profile is also reachable from the You tab,
  // which has no challenge form of its own.
  function challenge() {
    navigation.navigate('DuelsTab', {
      screen: 'CreateChallenge',
      initial: false,
      params: { preselect: profile.user.id },
    });
  }

  return (
    <Screen scroll>
      <View style={styles.head}>
        <Avatar name={name} size={72} />
        <Text style={styles.username}>{name}</Text>
        {profile.relationship === 'friends' ? <Badge label="Friends" tone="accent" /> : null}
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {profile.relationship === 'none' ? (
        <Button title={busy ? 'Sending…' : 'Add Friend'} icon="person-add" onPress={addFriend} disabled={busy} />
      ) : null}
      {profile.relationship === 'request_sent' ? (
        <Button title="Friend request sent ⏳" variant="outline" disabled onPress={() => {}} />
      ) : null}
      {profile.relationship === 'request_received' ? (
        <Button
          title={busy ? 'Accepting…' : 'Accept Friend Request'}
          icon="checkmark-circle"
          onPress={acceptFriend}
          disabled={busy}
        />
      ) : null}

      <Card style={styles.recordCard}>
        <Text style={styles.cardHead}>RECORD</Text>
        <View style={styles.recordRow}>
          <Stat label="W" value={r.wins} color={colors.accent} styles={styles} />
          <Stat label="L" value={r.losses} color={colors.danger} styles={styles} />
          <Stat label="T" value={r.ties} color={colors.muted} styles={styles} />
          <Stat label="Played" value={r.played} color={colors.text} styles={styles} />
        </View>
        {r.streak?.count > 0 ? (
          <Text style={styles.streak}>
            {r.streak.type === 'win' ? '🔥' : ''} {r.streak.count}-{r.streak.type} streak
          </Text>
        ) : null}
      </Card>

      {vs ? (
        <Card style={styles.recordCard}>
          <Text style={styles.cardHead}>YOU vs {name.toUpperCase()}</Text>
          <Text style={styles.vsLine}>
            <Text style={{ color: colors.accent, fontWeight: '800' }}>{vs.wins}</Text> – {vs.losses}
            {vs.ties > 0 ? ` – ${vs.ties}` : ''} <Text style={styles.vsMuted}>({vs.played} duels)</Text>
          </Text>
        </Card>
      ) : (
        <Text style={styles.note}>You haven't finished a 1v1 against {name} yet.</Text>
      )}

      <View style={styles.challengeWrap}>
        <Button title={`Challenge ${name}`} icon="flash" onPress={challenge} />
      </View>

      {history.length > 0 ? (
        <Card style={styles.historyCard}>
          <Text style={styles.cardHead}>PREVIOUS DUELS</Text>
          {history.map((h, i) => (
            <View key={i} style={[styles.historyRow, i > 0 && styles.historyDivider]}>
              <View style={[styles.pill, { backgroundColor: outcomeTint(h.outcome, colors) }]}>
                <Text style={[styles.pillText, { color: outcomeColor(h.outcome, colors) }]}>
                  {h.outcome === 'win' ? 'W' : h.outcome === 'loss' ? 'L' : 'T'}
                </Text>
              </View>
              <Text style={styles.historyScore}>
                {fmtPoints(h.points_for)} <Text style={styles.vsMuted}>–</Text> {fmtPoints(h.points_against)}
              </Text>
              <Text style={styles.historyDate}>{fmtDate(h.settled_at)}</Text>
            </View>
          ))}
        </Card>
      ) : null}

      <Pressable onPress={confirmBlock} hitSlop={8} style={{ alignSelf: 'center', marginTop: 28 }}>
        <Text style={styles.blockLink}>Block {profile.user.username}</Text>
      </Pressable>

    </Screen>
  );
}

function fmtPoints(n) {
  if (n == null) return '—';
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function fmtDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function outcomeColor(outcome, colors) {
  if (outcome === 'win') return colors.accent;
  if (outcome === 'loss') return colors.danger;
  return colors.muted;
}

function outcomeTint(outcome, colors) {
  if (outcome === 'win') return colors.accentSoft;
  if (outcome === 'loss') return colors.dangerSoft || colors.cardElevated;
  return colors.cardElevated;
}

function Stat({ label, value, color, styles }) {
  return (
    <View style={styles.stat}>
      <Text style={[styles.statValue, { color }]}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    blockLink: { color: colors.placeholder, fontSize: 13, textDecorationLine: 'underline' },
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    head: { alignItems: 'center', gap: spacing.sm, marginBottom: spacing.lg },
    username: { color: colors.text, fontSize: 26, fontFamily: fonts.hero, paddingRight: 4 },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.md },
    recordCard: { marginTop: spacing.lg },
    cardHead: { color: colors.muted, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 2, textAlign: 'center', marginBottom: spacing.md, textTransform: 'uppercase' },
    recordRow: { flexDirection: 'row', justifyContent: 'space-around' },
    stat: { alignItems: 'center' },
    statValue: { fontSize: 24, fontFamily: fonts.hero },
    statLabel: { color: colors.muted, fontSize: font.caption, fontWeight: '700', marginTop: 2 },
    streak: { color: colors.muted, fontSize: font.small, textAlign: 'center', marginTop: spacing.md },
    vsLine: { color: colors.text, fontSize: 24, fontFamily: fonts.hero, textAlign: 'center', paddingRight: 4 },
    vsMuted: { color: colors.muted, fontSize: font.small, fontWeight: '400' },
    challengeWrap: { marginTop: spacing.lg },
    historyCard: { marginTop: spacing.lg, paddingVertical: spacing.md },
    historyRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10 },
    historyDivider: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.borderSubtle },
    pill: { width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center' },
    pillText: { fontSize: font.caption, fontFamily: fonts.bodyBlack },
    historyScore: { flex: 1, color: colors.text, fontSize: font.body, fontWeight: '700', marginLeft: spacing.md },
    historyDate: { color: colors.muted, fontSize: font.small },
    note: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.lg },
  });
```
