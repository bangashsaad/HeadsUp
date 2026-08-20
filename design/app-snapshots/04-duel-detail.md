# Duel detail — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

One duel's full picture: parties, status, complete terms, scoring chart, stake/pot, and the actions that status allows (accept / decline / counter / cancel / enter draft / open live / results / rematch).

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

## The screen source (`src/screens/DuelDetailScreen.js`)

```jsx
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { etDayISO } from '../time';
import { getDuel, respondToDuel, startWithGroup, getLiveResult } from '../api/duels';
import { formatDateTime } from '../utils/datetime';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, statusTone, withAlpha } from '../theme';
import { Screen, Card, Avatar, Badge, Button, SectionHeader, GhostText } from '../components/ui';

const SPORT_LABEL = {
  nfl: '🏈 Football',
  nba: '🏀 Basketball',
  wnba: '🏀 WNBA',
  mlb: '⚾️ Baseball',
};

function clockLabel(secs) {
  if (!secs) return '—';
  if (secs < 3600) return `${secs}s per pick`;
  return `${secs / 3600}h per pick (async)`;
}

const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const prettyKey = (k) => k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

// "Tonight's games (Jul 13)" for the duel's slate day — ET, like the server.
function slateTermLabel(iso) {
  const et = (ms) => etDayISO(ms);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const d = new Date(`${iso}T12:00:00Z`);
  const md = `${months[d.getUTCMonth()]} ${d.getUTCDate()}`;
  if (iso === et(Date.now())) return `Tonight's games (${md})`;
  if (iso === et(Date.now() + 24 * 3600 * 1000)) return `Tomorrow's games (${md})`;
  return `${md} games only`;
}

export default function DuelDetailScreen({ route, navigation }) {
  const { id } = route.params;
  const { token, user, refreshUser } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duel, setDuel] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await getDuel(token, id);
      setDuel(res.duel);
    } catch (e) {
      setError(e.message);
    }
  }, [token, id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  async function act(action) {
    setBusy(true);
    setError(null);
    try {
      await respondToDuel(token, id, action);
      refreshUser(); // stakes/refunds just moved — pull the fresh balance
      navigation.goBack();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  async function forceStart() {
    setBusy(true);
    setError(null);
    try {
      await startWithGroup(token, id);
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  function Term({ label, value, first }) {
    return (
      <View style={[styles.term, !first && styles.termDivider]}>
        <Text style={styles.termLabel}>{label}</Text>
        <Text style={styles.termValue}>{value}</Text>
      </View>
    );
  }

  if (!duel && error) {
    return (
      <Screen>
        <EmptyState
          icon="cloud-offline-outline"
          title="Couldn't load this duel"
          subtitle={error}
          action={<Button title="Try again" icon="refresh" onPress={() => { setError(null); load(); }} />}
        />
      </Screen>
    );
  }

  if (!duel) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  const group = duel.group === true;
  const seats = duel.participants || [];
  const mySeat = seats.find((p) => p.user?.id === user?.id);
  const seatedCount = seats.filter((p) => p.status === 'accepted').length;
  const canRespondSeat = group && duel.status === 'pending' && mySeat?.status === 'invited';
  const isOpponentPending = !group && duel.role === 'opponent' && duel.status === 'pending';
  const isChallengerPending = duel.role === 'challenger' && duel.status === 'pending';
  const scoring = Object.entries(duel.scoring_rules || {});
  const shareable = ['pending', 'accepted', 'drafting', 'drafted', 'settled'].includes(duel.status);

  function shareMatchup() {
    const stage =
      duel.status === 'drafted'
        ? 'Lineups are locked — scoring is live!'
        : duel.status === 'settled'
          ? 'The final is in.'
          : duel.status === 'pending'
            ? 'The challenge is on the table.'
            : `We draft ${formatDateTime(duel.draft_starts_at)}.`;
    const matchup = group
      ? `⚔️ Heads Up group duel — ${duel.party_size} players, ${SPORT_LABEL[duel.sport] || duel.sport}. ${stage}`
      : `⚔️ Heads Up fantasy duel: me vs ${duel.opponent.username} — ${SPORT_LABEL[duel.sport] || duel.sport}. ${stage}`;
    Share.share({ message: matchup }).catch(() => {});
  }

  return (
    <Screen scroll>
      {group ? (
        <View style={styles.seatsWrap}>
          {seats.map((p) => {
            const me = p.user?.id === user?.id;
            const name = me ? 'You' : p.user?.username || 'Player';
            return (
              <Pressable
                key={p.seat}
                disabled={me || !p.user}
                onPress={() => navigation.navigate('UserProfile', { id: p.user.id, username: p.user.username })}
                style={({ pressed }) => [
                  styles.seatChip,
                  p.status === 'declined' && { opacity: 0.45 },
                  pressed && { opacity: 0.7 },
                ]}
              >
                <Avatar name={name} size={40} />
                <Text style={styles.seatName} numberOfLines={1}>
                  {name}
                </Text>
                <SeatStatus seat={p} colors={colors} styles={styles} />
              </Pressable>
            );
          })}
        </View>
      ) : (
        <View style={styles.header}>
          <View style={styles.side}>
            <Avatar name="You" size={56} />
            <Text style={styles.sideName}>You</Text>
          </View>
          <GhostText size={28} color={withAlpha(colors.placeholder, 0.9)} strokeWidth={1.3} style={{ marginHorizontal: 4 }}>
            VS
          </GhostText>
          <Pressable
            style={({ pressed }) => [styles.side, pressed && { opacity: 0.7 }]}
            onPress={() => navigation.navigate('UserProfile', { id: duel.opponent.id, username: duel.opponent.username })}
          >
            <Avatar name={duel.opponent.username} size={56} />
            <Text style={styles.sideName} numberOfLines={1}>
              {duel.opponent.username}
            </Text>
          </Pressable>
        </View>
      )}

      <View style={styles.statusRow}>
        <Badge label={duel.status} tone={statusTone(duel.status)} dot />
        {duel.stake_coins > 0 ? (
          <View style={styles.potPill}>
            <Text style={styles.potText}>◎ {(duel.pot_coins || duel.stake_coins * 2).toLocaleString()} POT</Text>
          </View>
        ) : null}
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Card padded={false}>
        <Term label="Sport" value={SPORT_LABEL[duel.sport] || duel.sport} first />
        <Term label="Draft type" value={cap(duel.draft_type)} />
        <Term label="Lineup" value={`${cap((duel.lineup_template || '').split('_')[1] || '')} · ${duel.roster_size} slots`} />
        <Term label="Pick clock" value={clockLabel(duel.pick_clock_seconds)} />
        <Term label="Stake" value={duel.stake_coins > 0 ? `◎ ${duel.stake_coins.toLocaleString()} each` : 'Friendly'} />
        {duel.slate_date ? <Term label="Slate" value={slateTermLabel(duel.slate_date)} /> : null}
        <Term label="Draft starts" value={formatDateTime(duel.draft_starts_at)} />
      </Card>

      <SectionHeader>Scoring chart</SectionHeader>
      <Card padded={false}>
        {scoring.map(([key, value], i) => (
          <Term key={key} label={prettyKey(key)} value={String(value)} first={i === 0} />
        ))}
      </Card>

      <View style={styles.actions}>
        {isOpponentPending ? (
          <>
            <Button
              title={duel.stake_coins > 0 ? `Accept & Stake ◎ ${duel.stake_coins.toLocaleString()}` : 'Accept Challenge'}
              icon="checkmark-circle"
              onPress={() => act('accept')}
              disabled={busy}
            />
            <View style={styles.twoUp}>
              <Button title="Counter" variant="outline" full={false} style={{ flex: 1 }} onPress={() => goCounter(navigation, duel)} disabled={busy} />
              <Button title="Decline" variant="danger" full={false} style={{ flex: 1 }} onPress={() => act('decline')} disabled={busy} />
            </View>
          </>
        ) : null}

        {canRespondSeat ? (
          <>
            <Button
              title={duel.stake_coins > 0 ? `Accept Seat & Stake ◎ ${duel.stake_coins.toLocaleString()}` : 'Accept Your Seat'}
              icon="checkmark-circle"
              onPress={() => act('accept')}
              disabled={busy}
            />
            <Button title="Decline" variant="danger" icon="close-circle" onPress={() => act('decline')} disabled={busy} />
            <Text style={styles.locked}>Everyone drafts their own team — best total wins.</Text>
          </>
        ) : null}

        {group && duel.status === 'pending' && !canRespondSeat && !isChallengerPending ? (
          <Text style={styles.locked}>⏳ Waiting on the other invites…</Text>
        ) : null}

        {isChallengerPending ? (
          <>
            {group && seatedCount >= 2 ? (
              <Button
                title={`Start with current group (${seatedCount} in)`}
                icon="play"
                onPress={forceStart}
                disabled={busy}
              />
            ) : null}
            {group && seatedCount < 2 ? (
              <Text style={styles.locked}>⏳ You can start once at least one friend accepts.</Text>
            ) : null}
            <Button title="Cancel challenge" variant="danger" icon="close-circle" onPress={() => act('cancel')} disabled={busy} />
          </>
        ) : null}

        {duel.status === 'accepted' || duel.status === 'drafting' ? (
          <Button
            title={duel.status === 'drafting' ? 'Resume Live Draft' : 'Enter Draft Room'}
            icon="play"
            onPress={() => navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })}
          />
        ) : null}

        {duel.status === 'drafted' ? (
          <>
            <LiveScore
              token={token}
              id={duel.id}
              styles={styles}
              colors={colors}
              onOpen={() => navigation.navigate('LiveMatchup', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Button
              title="Watch Live Matchup"
              icon="pulse"
              onPress={() => navigation.navigate('LiveMatchup', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Button
              title="View Drafted Lineups"
              variant="outline"
              icon="list"
              onPress={() => navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Text style={styles.locked}>⏳ Lineups locked — the winner is declared once the games finish.</Text>
          </>
        ) : null}

        {duel.status === 'settled' ? (
          <Button
            title={
              duel.my_outcome === 'win'
                ? 'View Result — You won! 🏆'
                : duel.my_outcome === 'tie'
                  ? 'View Result — Tie 🤝'
                  : 'View Result'
            }
            icon="podium"
            onPress={() => navigation.navigate('Results', { id: duel.id, opponentName: duel.opponent.username })}
          />
        ) : null}

        {shareable ? <Button title="Share matchup" icon="share-outline" variant="outline" onPress={shareMatchup} /> : null}
      </View>
    </Screen>
  );
}

function SeatStatus({ seat, colors, styles }) {
  const cfg =
    seat.seat === 0
      ? { icon: 'star', color: colors.accent, label: 'Host' }
      : seat.status === 'accepted'
        ? { icon: 'checkmark-circle', color: colors.accent, label: 'In' }
        : seat.status === 'declined'
          ? { icon: 'close-circle', color: colors.danger, label: 'Out' }
          : { icon: 'time-outline', color: colors.muted, label: 'Invited' };

  return (
    <View style={styles.seatStatusRow}>
      <Ionicons name={cfg.icon} size={13} color={cfg.color} />
      <Text style={[styles.seatStatus, { color: cfg.color }]}>{cfg.label}</Text>
    </View>
  );
}

function LiveScore({ token, id, styles, colors, onOpen }) {
  const [live, setLive] = useState(null);
  const [started, setStarted] = useState(false);
  const timer = useRef(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
        try {
          const res = await getLiveResult(token, id);
          if (active) {
            setLive(res);
            setStarted(true);
          }
        } catch (e) {
          // 409 once settled / not live — stop polling, leave last snapshot.
          if (active) setStarted(true);
        }
      };
      tick();
      timer.current = setInterval(tick, 20000);
      return () => {
        active = false;
        if (timer.current) clearInterval(timer.current);
      };
    }, [token, id])
  );

  if (!live) {
    return (
      <Card style={styles.liveCard}>
        <Text style={styles.liveHead}>LIVE SCORE</Text>
        <Text style={styles.liveWaiting}>{started ? 'Waiting on the first game to tip off…' : 'Loading…'}</Text>
      </Card>
    );
  }

  const g = live.games || {};
  const gameLine = [g.final ? `${g.final} final` : null, g.live ? `${g.live} live` : null, g.upcoming ? `${g.upcoming} upcoming` : null]
    .filter(Boolean)
    .join(' · ');

  // Group: ranked standings strip (sides arrive best-total-first).
  if (!live.challenger && (live.sides || []).length > 0) {
    return (
      <Pressable onPress={onOpen} style={({ pressed }) => pressed && { opacity: 0.85 }}>
        <Card style={styles.liveCard}>
          <View style={styles.liveTop}>
            <Text style={styles.liveHead}>LIVE STANDINGS</Text>
            {g.live > 0 ? <Badge label="LIVE" tone="danger" dot /> : null}
          </View>
          {live.sides.map((s, i) => (
            <View key={s.user.id} style={styles.liveStandRow}>
              <Text style={styles.liveRank}>{i + 1}</Text>
              <Text style={[styles.liveStandName, s.is_me && { color: colors.accent }]} numberOfLines={1}>
                {s.is_me ? 'You' : s.user.username}
              </Text>
              <Text style={[styles.liveStandPts, i === 0 && { color: colors.accent }]}>{(s.total ?? 0).toFixed(1)}</Text>
            </View>
          ))}
          <Text style={styles.liveGames}>{gameLine || 'No games in the window yet'} › tap for full standings</Text>
        </Card>
      </Pressable>
    );
  }

  const me = live.challenger.is_me ? live.challenger : live.opponent;
  const them = live.challenger.is_me ? live.opponent : live.challenger;
  const meLeads = live.leader_id && me.user.id === live.leader_id;
  const themLead = live.leader_id && them.user.id === live.leader_id;

  return (
    <Pressable onPress={onOpen} style={({ pressed }) => pressed && { opacity: 0.85 }}>
      <Card style={styles.liveCard}>
        <View style={styles.liveTop}>
          <Text style={styles.liveHead}>LIVE SCORE</Text>
          {g.live > 0 ? <Badge label="LIVE" tone="danger" dot /> : null}
        </View>
        <View style={styles.liveRow}>
          <LiveSide label="You" total={me.total} lead={meLeads} colors={colors} styles={styles} />
          <Text style={styles.liveDash}>–</Text>
          <LiveSide label={them.user.username} total={them.total} lead={themLead} colors={colors} styles={styles} />
        </View>
        <Text style={styles.liveGames}>{gameLine || 'No games in the window yet'} › tap for full matchup</Text>
      </Card>
    </Pressable>
  );
}

function LiveSide({ label, total, lead, colors, styles }) {
  return (
    <View style={styles.liveSide}>
      <Text style={[styles.liveTotal, lead && { color: colors.accent }]}>{(total ?? 0).toFixed(1)}</Text>
      <Text style={styles.liveName} numberOfLines={1}>
        {label}
      </Text>
      {lead ? <Text style={styles.liveLeading}>LEADING</Text> : <Text style={styles.liveLeadingSpacer} />}
    </View>
  );
}

function goCounter(navigation, duel) {
  navigation.navigate('Counter', {
    id: duel.id,
    initial: {
      sport: duel.sport,
      lineup_template: duel.lineup_template,
      pick_clock_seconds: duel.pick_clock_seconds,
      stake_coins: duel.stake_coins,
      slate_date: duel.slate_date,
    },
  });
}

const makeStyles = (colors) =>
  StyleSheet.create({
    loading: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md },
    side: { alignItems: 'center', flex: 1 },
    sideName: { color: colors.text, fontSize: 16, fontFamily: fonts.condBold, letterSpacing: 0.5, marginTop: spacing.sm, maxWidth: '90%' },
    statusRow: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: spacing.sm, marginBottom: spacing.lg },
    potPill: {
      backgroundColor: withAlpha(colors.gold, 0.14),
      borderColor: withAlpha(colors.gold, 0.45),
      borderWidth: 1,
      borderRadius: radius.pill,
      paddingHorizontal: spacing.md,
      paddingVertical: 4,
    },
    potText: { color: colors.gold, fontSize: 11, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.md },
    term: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 13, paddingHorizontal: spacing.lg },
    termDivider: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    termLabel: { color: colors.muted, fontSize: 12.5, fontFamily: fonts.bodySemi },
    termValue: { color: colors.text, fontSize: 15, fontFamily: fonts.condBold, letterSpacing: 0.3 },
    actions: { marginTop: spacing.xl, gap: spacing.md },
    twoUp: { flexDirection: 'row', gap: spacing.md },
    locked: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.sm, lineHeight: 21 },
    liveCard: { borderColor: colors.accentBorder },
    liveTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm, marginBottom: spacing.sm },
    liveHead: { color: colors.muted, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, textAlign: 'center' },
    liveWaiting: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.xs },
    liveRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
    liveSide: { flex: 1, alignItems: 'center' },
    liveTotal: { color: colors.text, fontSize: 40, lineHeight: 42, fontFamily: fonts.hero, paddingRight: 3 },
    liveName: { color: colors.muted, fontSize: font.small, marginTop: 2, maxWidth: '90%' },
    liveLeading: { color: colors.accent, fontSize: 10, fontWeight: '800', letterSpacing: 1, marginTop: 2 },
    liveLeadingSpacer: { fontSize: 10, marginTop: 2, height: 13 },
    liveDash: { color: colors.placeholder, fontSize: font.title, fontWeight: '800', paddingHorizontal: spacing.sm },
    liveGames: { color: colors.muted, fontSize: font.caption, textAlign: 'center', marginTop: spacing.sm },
    liveStandRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: 5 },
    liveRank: { color: colors.placeholder, fontSize: font.small, fontWeight: '800', width: 18 },
    liveStandName: { color: colors.text, fontSize: font.body, fontWeight: '600', flex: 1 },
    liveStandPts: { color: colors.text, fontSize: 19, fontFamily: fonts.hero },
    seatsWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.md, justifyContent: 'center' },
    seatChip: {
      flexGrow: 1,
      flexBasis: '30%',
      maxWidth: '48%',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: radius.lg,
      paddingVertical: spacing.md,
      paddingHorizontal: spacing.sm,
    },
    seatName: { color: colors.text, fontFamily: fonts.condBold, fontSize: 14, marginTop: spacing.xs, maxWidth: '95%' },
    seatStatusRow: { flexDirection: 'row', alignItems: 'center', gap: 3, marginTop: 3 },
    seatStatus: { fontSize: 11, fontWeight: '700' },
  });
```
