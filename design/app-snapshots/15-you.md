# Profile (YOU tab) — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Your card: record hero (W–L, streak, win rate), splits, YOUR CREW (friends with per-rival head-to-head), WANTS IN requests inbox, friend groups, and the account rows (coin wallet, verify email, settings, change password, sign out, delete account).

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

## The screen source (`src/screens/ProfileScreen.js`)

```jsx
import { useCallback, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getMyStats, getAchievements, getLeaderboard } from '../api/me';
import { listRequests } from '../api/social';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { Screen, Card, Avatar, Button, StatTile, SectionHeader, CondTitle, Kicker } from '../components/ui';

function Row({ icon, label, sublabel, onPress, danger, count }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
      <View style={[styles.rowIcon, danger && { backgroundColor: colors.dangerSoft }]}>
        <Ionicons name={icon} size={18} color={danger ? colors.danger : colors.accent} />
      </View>
      <View style={{ flex: 1 }}>
        <Text style={[styles.rowLabel, danger && { color: colors.danger }]}>{label}</Text>
        {sublabel ? <Text style={styles.rowSub}>{sublabel}</Text> : null}
      </View>
      {count > 0 ? (
        <View style={styles.rowCount}>
          <Text style={styles.rowCountText}>{count}</Text>
        </View>
      ) : null}
      <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
    </Pressable>
  );
}

const RANK_COLOR = (colors, rank) =>
  rank === 1 ? colors.gold : rank === 2 ? colors.silver : rank === 3 ? colors.bronze : colors.placeholder;

export default function ProfileScreen({ navigation }) {
  const { user, token, signOut, refreshUser } = useAuth();
  const { colors, scheme } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [stats, setStats] = useState(null);
  const [trophies, setTrophies] = useState([]);
  const [standings, setStandings] = useState([]);
  const [requestCount, setRequestCount] = useState(0);
  const [openTrophy, setOpenTrophy] = useState(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      refreshUser(); // keep the coin balance honest whenever YOU opens
      getMyStats(token)
        .then((s) => active && setStats(s))
        .catch(() => {});
      getAchievements(token)
        .then((r) => active && setTrophies(r.achievements || []))
        .catch(() => {});
      getLeaderboard(token)
        .then((r) => active && setStandings(r.leaderboard || []))
        .catch(() => {});
      listRequests(token)
        .then((r) => active && setRequestCount((r.requests || []).length))
        .catch(() => {});
      return () => {
        active = false;
      };
    }, [token])
  );

  function invite() {
    Share.share({
      message: `Play me 1-on-1 in Heads Up fantasy 🏀⚾️ — draft a lineup, winner takes bragging rights. Add me: my username is ${user?.username}.`,
    }).catch(() => {});
  }

  function howToPlay() {
    Alert.alert(
      'How to play',
      'Challenge a friend to a 1-on-1 fantasy duel — or invite up to 3 for a group match. Agree on the sport, lineup and scoring, draft your rosters live (snake order, ticking clock), then the winner is declared automatically once the games finish. Best total takes it.'
    );
  }

  const rec = stats?.record;
  const h2h = stats?.head_to_head || [];
  const h2hById = new Map(h2h.map((r) => [String(r.opponent.id), r]));
  const winPct = rec ? Math.round((rec.win_pct || 0) * (rec.win_pct <= 1 ? 100 : 1)) : null;
  const ptDiff = rec ? Math.round(((rec.points_for || 0) - (rec.points_against || 0)) * 10) / 10 : 0;
  const myRank = standings.find((r) => String(r.user?.id) === String(user?.id))?.rank;
  const earned = trophies.filter((t) => t.earned).length;

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView contentContainerStyle={{ paddingBottom: spacing.xxl }} showsVerticalScrollIndicator={false}>
        {/* Identity. The cyan glow is a dark-mode device; light stays clean. */}
        <LinearGradient
          colors={scheme === 'dark' ? [withAlpha(colors.cyan, 0.12), 'transparent'] : ['transparent', 'transparent']}
          start={{ x: 0.8, y: 0 }}
          end={{ x: 0.4, y: 1 }}
          style={styles.headerZone}
        >
          <View style={styles.idRow}>
            <Avatar name={user?.username || '?'} size={62} />
            <View style={{ flex: 1 }}>
              <CondTitle size={26} numberOfLines={1} style={{ paddingRight: 4 }}>
                {(user?.username || '?').toUpperCase()}
              </CondTitle>
              <View style={styles.chipRow}>
                <Pressable onPress={() => navigation.navigate('CoinHistory')} style={[styles.idChip, styles.coinChip]}>
                  <Text style={[styles.idChipText, { color: colors.gold }]}>◎ {(user?.coins ?? 0).toLocaleString()}</Text>
                </Pressable>
                {rec?.streak?.count > 0 ? (
                  <View style={styles.idChip}>
                    <Text
                      style={[
                        styles.idChipText,
                        { color: rec.streak.type === 'win' ? colors.gold : rec.streak.type === 'loss' ? colors.danger : colors.muted },
                      ]}
                    >
                      {rec.streak.type === 'win' ? `🔥 W${rec.streak.count} STREAK` : `${rec.streak.type[0].toUpperCase()}${rec.streak.count} STREAK`}
                    </Text>
                  </View>
                ) : null}
                {myRank ? (
                  <View style={styles.idChip}>
                    <Text style={[styles.idChipText, { color: colors.muted }]}>#{myRank} OF FRIENDS</Text>
                  </View>
                ) : null}
              </View>
            </View>
          </View>

          <View style={styles.statGrid}>
            <StatTile value={rec?.wins ?? 0} label="Wins" color={colors.accent} />
            <StatTile value={rec?.losses ?? 0} label="Losses" color={colors.danger} />
            <StatTile value={winPct != null ? `${winPct}%` : '—'} label="Win rate" />
            <StatTile value={`${ptDiff >= 0 ? '+' : ''}${ptDiff}`} label="Pt diff" />
          </View>
        </LinearGradient>

        <View style={{ paddingHorizontal: spacing.lg }}>
          {/* Trophy case */}
          {trophies.length > 0 ? (
            <SectionHeader hint={`${earned} / ${trophies.length}`}>Trophy case</SectionHeader>
          ) : null}
        </View>
        {trophies.length > 0 ? (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.trophyRow}>
            {trophies.map((t) => (
              <Pressable
                key={t.key}
                onPress={() => setOpenTrophy(t)}
                style={({ pressed }) => [styles.trophyTile, t.earned ? styles.trophyTileOn : styles.trophyTileOff, pressed && { opacity: 0.8 }]}
              >
                <Ionicons name={t.icon} size={21} color={t.earned ? colors.accent : colors.placeholder} />
                <Text style={[styles.trophyTitle, !t.earned && { color: colors.muted }]} numberOfLines={1}>
                  {t.title}
                </Text>
                <Text style={styles.trophySub} numberOfLines={1}>
                  {t.earned ? '✓ EARNED' : `${Math.min(t.value, t.threshold)}/${t.threshold}`}
                </Text>
              </Pressable>
            ))}
          </ScrollView>
        ) : null}

        <View style={{ paddingHorizontal: spacing.lg }}>
          {/* Standings among friends */}
          <SectionHeader hint={requestCount > 0 ? `${requestCount} REQUEST${requestCount > 1 ? 'S' : ''}` : undefined}>
            Friend standings
          </SectionHeader>
          {standings.length === 0 ? (
            <Card>
              <Text style={styles.emptyStandings}>No friends yet. Add some and the standings show up here.</Text>
              <Button title="Add friends" size="sm" full={false} style={{ marginTop: spacing.md, alignSelf: 'flex-start' }} onPress={() => navigation.navigate('Search')} />
            </Card>
          ) : (
            <View style={{ gap: 7 }}>
              {standings.map((r) => {
                const isMe = String(r.user?.id) === String(user?.id);
                const vs = h2hById.get(String(r.user?.id));
                return (
                  <Pressable
                    key={r.user?.id ?? r.rank}
                    disabled={isMe}
                    onPress={() => navigation.navigate('UserProfile', { id: r.user.id, username: r.user.username })}
                    style={({ pressed }) => [styles.standingRow, isMe && styles.standingRowMe, pressed && { opacity: 0.8 }]}
                  >
                    <CondTitle size={15} color={RANK_COLOR(colors, r.rank)} style={{ width: 20 }}>
                      {r.rank}
                    </CondTitle>
                    <Avatar name={isMe ? user?.username : r.user?.username} size={30} />
                    <View style={{ flex: 1 }}>
                      <Text style={[styles.standingName, isMe && { color: colors.accent }]} numberOfLines={1}>
                        {isMe ? `${user?.username} · you` : r.user?.username}
                      </Text>
                      <Text style={styles.standingSub} numberOfLines={1}>
                        {isMe
                          ? myRank === 1
                            ? 'Top of the standings — defend it'
                            : 'Climb the board — win a duel'
                          : vs
                            ? `Your record vs: ${vs.wins}–${vs.losses}${vs.ties ? `–${vs.ties}` : ''}`
                            : 'No duels yet — call them out'}
                      </Text>
                    </View>
                    <Text style={styles.standingRec}>
                      {r.wins}–{r.losses}
                      {r.ties ? `–${r.ties}` : ''}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          )}

          {/* Menu */}
          <Card padded={false} style={{ marginTop: spacing.lg }}>
            <Row icon="people-outline" label="Manage friends" sublabel="Friends, search, invites" onPress={() => navigation.navigate('Friends')} />
            <View style={styles.menuDivider} />
            <Row icon="mail-unread-outline" label="Friend requests" count={requestCount} onPress={() => navigation.navigate('Requests')} />
            <View style={styles.menuDivider} />
            <Row icon="person-add-outline" label="Invite a friend" sublabel="Share your username to duel" onPress={invite} />
            <View style={styles.menuDivider} />
            <Row
              icon="server-outline"
              label="Coin wallet"
              sublabel={`◎ ${(user?.coins ?? 0).toLocaleString()} — stakes, pots & bonuses`}
              onPress={() => navigation.navigate('CoinHistory')}
            />
            <View style={styles.menuDivider} />
            <Row icon="settings-outline" label="Settings" sublabel="Appearance, preferences, account" onPress={() => navigation.navigate('Settings')} />
            <View style={styles.menuDivider} />
            <Row icon="help-circle-outline" label="How to play" onPress={howToPlay} />
          </Card>

          <View style={{ marginTop: spacing.xl }}>
            <Button title="Log out" variant="danger" icon="log-out-outline" onPress={signOut} />
          </View>
        </View>
      </ScrollView>

      <TrophySheet trophy={openTrophy} onClose={() => setOpenTrophy(null)} styles={styles} colors={colors} />
    </Screen>
  );
}

// Tap a trophy → what it means and how close you are.
function TrophySheet({ trophy, onClose, styles, colors }) {
  if (!trophy) return null;
  const earned = trophy.earned;
  const progress = Math.min(trophy.value / Math.max(trophy.threshold, 1), 1);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.sheetWrap}>
        <Pressable style={styles.sheetBackdrop} onPress={onClose} />
        <View style={styles.sheet}>
          <View style={styles.sheetHandle} />
          <View
            style={[
              styles.sheetTrophyIcon,
              { backgroundColor: earned ? colors.accentSoft : colors.card, borderColor: earned ? colors.accentBorder : colors.border },
            ]}
          >
            <Ionicons name={trophy.icon} size={34} color={earned ? colors.accent : colors.placeholder} />
          </View>
          <CondTitle size={24} style={{ marginTop: spacing.md }}>
            {trophy.title.toUpperCase()}
          </CondTitle>
          <Text style={styles.sheetDesc}>{trophy.description}</Text>

          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${Math.round(progress * 100)}%`, backgroundColor: earned ? colors.accent : colors.muted }]} />
          </View>
          <Kicker size={11} tracking={1} color={earned ? colors.accent : colors.muted} style={{ marginTop: spacing.sm }}>
            {earned ? '✓ Earned' : `${Math.min(trophy.value, trophy.threshold)} of ${trophy.threshold}`}
          </Kicker>
        </View>
      </View>
    </Modal>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
    idRow: { flexDirection: 'row', alignItems: 'center', gap: 14 },
    chipRow: { flexDirection: 'row', gap: 6, marginTop: 6 },
    idChip: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingVertical: 3,
      paddingHorizontal: 9,
    },
    idChipText: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    coinChip: { borderColor: withAlpha(colors.gold, 0.45), backgroundColor: withAlpha(colors.gold, 0.1) },
    statGrid: { flexDirection: 'row', gap: 8, marginTop: spacing.lg },
    trophyRow: { gap: 8, paddingHorizontal: spacing.lg },
    trophyTile: {
      width: 86,
      borderRadius: 12,
      borderWidth: 1,
      paddingVertical: 10,
      alignItems: 'center',
      gap: 5,
    },
    trophyTileOn: { borderColor: withAlpha(colors.accent, 0.4), backgroundColor: withAlpha(colors.accent, 0.08) },
    trophyTileOff: { borderColor: colors.border, backgroundColor: colors.card, opacity: 0.55 },
    trophyTitle: { color: colors.text, fontSize: 9, fontFamily: fonts.bodyExtra, maxWidth: 78, textAlign: 'center' },
    trophySub: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
    emptyStandings: { color: colors.muted, fontSize: font.small, lineHeight: 19, fontFamily: fonts.body },
    standingRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
      paddingVertical: 10,
      paddingHorizontal: 12,
    },
    standingRowMe: { backgroundColor: withAlpha(colors.accent, 0.06), borderColor: withAlpha(colors.accent, 0.45) },
    standingName: { color: colors.text, fontSize: 13, fontFamily: fonts.bodyBold },
    standingSub: { color: colors.muted, fontSize: 10, marginTop: 1, fontFamily: fonts.body },
    standingRec: { color: colors.text, fontFamily: fonts.heroUpright, fontSize: 15 },
    row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    rowIcon: { width: 34, height: 34, borderRadius: 10, backgroundColor: colors.accentSoft, alignItems: 'center', justifyContent: 'center', marginRight: spacing.md },
    rowLabel: { color: colors.text, fontSize: font.bodyLg, fontFamily: fonts.bodySemi },
    rowSub: { color: colors.muted, fontSize: font.small, marginTop: 1, fontFamily: fonts.body },
    rowCount: {
      minWidth: 20,
      height: 20,
      borderRadius: 10,
      backgroundColor: colors.danger,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 5,
      marginRight: 6,
    },
    rowCountText: { color: '#fff', fontSize: 11, fontFamily: fonts.bodyExtra },
    menuDivider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle, marginLeft: 60 },
    sheetWrap: { flex: 1, justifyContent: 'flex-end' },
    sheetBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.55)' },
    sheet: {
      backgroundColor: colors.bg,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
      borderWidth: 1,
      borderColor: colors.border,
      padding: spacing.xl,
      paddingBottom: spacing.xxl,
      alignItems: 'center',
    },
    sheetHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.border, marginBottom: spacing.lg },
    sheetTrophyIcon: { width: 72, height: 72, borderRadius: 22, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
    sheetDesc: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.xs, lineHeight: 21, fontFamily: fonts.body },
    progressTrack: { alignSelf: 'stretch', height: 8, borderRadius: 4, backgroundColor: colors.bgElevated, marginTop: spacing.lg, overflow: 'hidden' },
    progressFill: { height: 8, borderRadius: 4 },
  });
```
