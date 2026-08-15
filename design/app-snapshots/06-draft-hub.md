# Draft hub (DRAFT tab) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Routes you into whichever draft is on the clock; otherwise the designed empty state (dashed G/G/F/F/FLX slots — the war room waiting to light up). Tab icon gets a blinking red dot when a draft is live somewhere.

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

## The screen source (`src/screens/DraftHubScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View, Pressable } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { listDuels } from '../api/duels';
import { setDraftLive } from '../state/attention';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, Badge, Button, Pulse, GhostText, Kicker, CondTitle, SkeletonList } from '../components/ui';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

function fmtClock(secs) {
  if (!secs) return null;
  if (secs < 120) return `${secs}S CLOCK`;
  if (secs < 7200) return `${Math.round(secs / 60)}M CLOCK`;
  return `${Math.round(secs / 3600)}H CLOCK`;
}

function fmtStart(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const hm = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  return sameDay ? `TODAY ${hm}` : `${d.toLocaleDateString([], { month: 'short', day: 'numeric' })} ${hm}`;
}

// One draftable duel — the ready-room card: faces, VS ghost, terms, big CTA.
function DraftCard({ duel, live, onEnter, myName, colors, styles }) {
  const names = duel.group
    ? (duel.participants || []).filter((p) => p.status !== 'declined').map((p) => p.user?.username || '?')
    : [myName || 'You', duel.opponent?.username || '?'];
  const chips = [
    `${SPORT_EMOJI[duel.sport] || '🎯'} ${(duel.sport || '').toUpperCase()}`,
    `${duel.roster_size} SLOTS`,
    fmtClock(duel.pick_clock_seconds),
    duel.group ? `${duel.party_size}-WAY` : 'SNAKE',
    !live ? fmtStart(duel.draft_starts_at) : null,
  ].filter(Boolean);

  return (
    <Pressable onPress={onEnter} style={({ pressed }) => [styles.card, live && styles.cardLive, pressed && { transform: [{ scale: 0.98 }] }]}>
      <View style={styles.ghostWrap} pointerEvents="none">
        <GhostText size={64} color={withAlpha(colors.text, 0.08)} strokeWidth={1}>
          VS
        </GhostText>
      </View>

      <View style={styles.cardTop}>
        {live ? (
          <Badge label="Draft live" tone="danger" blink />
        ) : (
          <Badge label="Ready to draft" tone="accent" />
        )}
        <Text style={styles.cardMeta}>{duel.group ? `${names.length} PLAYERS` : 'HEAD-TO-HEAD'}</Text>
      </View>

      <View style={styles.faceRow}>
        {names.slice(0, 4).map((n, i) => (
          <View key={`${n}-${i}`} style={{ marginLeft: i === 0 ? 0 : -10, zIndex: 9 - i }}>
            <Avatar name={n} size={40} />
          </View>
        ))}
        <CondTitle size={26} style={{ marginLeft: spacing.md, flex: 1 }} numberOfLines={2}>
          {live ? 'BACK ON THE CLOCK.' : `DRAFT VS ${(duel.group ? `${names.length - 1} RIVALS` : duel.opponent?.username || 'THEM').toUpperCase()}`}
        </CondTitle>
      </View>

      <View style={styles.chipRow}>
        {chips.map((c) => (
          <View key={c} style={styles.termChip}>
            <Text style={styles.termChipText}>{c}</Text>
          </View>
        ))}
      </View>

      <Pulse color={withAlpha(colors.accent, 0.3)} disabled={!live} style={{ marginTop: spacing.md, alignSelf: 'stretch' }}>
        <Button title={live ? 'Enter room →' : 'To the ready room →'} onPress={onEnter} />
      </Pulse>
    </Pressable>
  );
}

export default function DraftHubScreen({ navigation }) {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duels, setDuels] = useState(null);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listDuels(token);
      setDuels(res.duels || []);
      setError(null);
      setDraftLive((res.duels || []).some((d) => d.status === 'drafting'));
    } catch (e) {
      setError(e.message);
      if (duels == null) setDuels([]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
      const iv = setInterval(load, 30000);
      return () => clearInterval(iv);
    }, [load])
  );

  const drafting = (duels || []).filter((d) => d.status === 'drafting');
  const ready = (duels || []).filter((d) => d.status === 'accepted');

  function enter(d) {
    navigation.navigate('DuelsTab', {
      screen: 'DraftRoom',
      params: { id: d.id, opponentName: d.opponent?.username },
      initial: false,
    });
  }

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView contentContainerStyle={styles.body} showsVerticalScrollIndicator={false}>
        <Kicker tracking={3} style={{ textAlign: 'center', marginTop: spacing.sm }}>
          Draft room
        </Kicker>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {duels == null ? (
          <View style={{ marginTop: spacing.xl }}>
            <SkeletonList count={3} />
          </View>
        ) : drafting.length === 0 && ready.length === 0 ? (
          <View style={styles.emptyWrap}>
            <View style={styles.lockCoin}>
              <Ionicons name="timer-outline" size={30} color={colors.placeholder} />
            </View>
            <CondTitle size={20} color={colors.muted} style={{ textAlign: 'center', letterSpacing: 1 }}>
              NOTHING ON THE CLOCK
            </CondTitle>
            <Text style={styles.emptySub}>
              Accepted challenges land here as draft rooms. Call somebody out and the clock starts.
            </Text>
            <Button
              title="Start a challenge"
              style={{ marginTop: spacing.lg, alignSelf: 'center' }}
              full={false}
              onPress={() => navigation.navigate('DuelsTab', { screen: 'CreateChallenge', initial: false })}
            />
          </View>
        ) : (
          <View style={{ gap: spacing.md, marginTop: spacing.lg }}>
            {drafting.map((d) => (
              <DraftCard key={d.id} duel={d} live myName={user?.username} onEnter={() => enter(d)} colors={colors} styles={styles} />
            ))}
            {ready.map((d) => (
              <DraftCard key={d.id} duel={d} live={false} myName={user?.username} onEnter={() => enter(d)} colors={colors} styles={styles} />
            ))}
          </View>
        )}
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { padding: spacing.lg, paddingBottom: spacing.xxl },
    card: {
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      padding: spacing.lg,
      overflow: 'hidden',
    },
    cardLive: { borderColor: colors.dangerBorder, backgroundColor: colors.cardElevated },
    ghostWrap: { position: 'absolute', right: -4, top: -14 },
    cardTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    cardMeta: { color: colors.muted, fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 1 },
    faceRow: { flexDirection: 'row', alignItems: 'center', marginTop: spacing.md },
    chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 7, marginTop: spacing.md },
    termChip: {
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.bgElevated,
      borderRadius: 999,
      paddingVertical: 5,
      paddingHorizontal: 12,
    },
    termChipText: { fontSize: 11, fontFamily: fonts.bodyExtra, color: colors.muted, letterSpacing: 0.5 },
    emptyWrap: { alignItems: 'center', paddingTop: 120, paddingHorizontal: spacing.xl },
    lockCoin: {
      width: 64,
      height: 64,
      borderRadius: 20,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: spacing.lg,
    },
    emptySub: { color: colors.muted, fontSize: 13, textAlign: 'center', marginTop: spacing.sm, lineHeight: 19, fontFamily: fonts.body },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
```
