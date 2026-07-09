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
  const [crew, setCrew] = useState([]);
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
        .then((r) => active && setCrew(r.leaderboard || []))
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
  const myRank = crew.find((r) => String(r.user?.id) === String(user?.id))?.rank;
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
                    <Text style={[styles.idChipText, { color: colors.muted }]}>#{myRank} OF CREW</Text>
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
          {/* The crew */}
          <SectionHeader hint={requestCount > 0 ? `${requestCount} REQUEST${requestCount > 1 ? 'S' : ''}` : undefined}>
            The crew
          </SectionHeader>
          {crew.length === 0 ? (
            <Card>
              <Text style={styles.emptyCrew}>No crew yet. Add friends and the standings show up here.</Text>
              <Button title="Add friends" size="sm" full={false} style={{ marginTop: spacing.md, alignSelf: 'flex-start' }} onPress={() => navigation.navigate('Search')} />
            </Card>
          ) : (
            <View style={{ gap: 7 }}>
              {crew.map((r) => {
                const isMe = String(r.user?.id) === String(user?.id);
                const vs = h2hById.get(String(r.user?.id));
                return (
                  <Pressable
                    key={r.user?.id ?? r.rank}
                    disabled={isMe}
                    onPress={() => navigation.navigate('UserProfile', { id: r.user.id, username: r.user.username })}
                    style={({ pressed }) => [styles.crewRow, isMe && styles.crewRowMe, pressed && { opacity: 0.8 }]}
                  >
                    <CondTitle size={15} color={RANK_COLOR(colors, r.rank)} style={{ width: 20 }}>
                      {r.rank}
                    </CondTitle>
                    <Avatar name={isMe ? user?.username : r.user?.username} size={30} />
                    <View style={{ flex: 1 }}>
                      <Text style={[styles.crewName, isMe && { color: colors.accent }]} numberOfLines={1}>
                        {isMe ? `${user?.username} · you` : r.user?.username}
                      </Text>
                      <Text style={styles.crewSub} numberOfLines={1}>
                        {isMe
                          ? myRank === 1
                            ? 'Top of the crew — defend it'
                            : 'Climb the board — win a duel'
                          : vs
                            ? `Your record vs: ${vs.wins}–${vs.losses}${vs.ties ? `–${vs.ties}` : ''}`
                            : 'No duels yet — call them out'}
                      </Text>
                    </View>
                    <Text style={styles.crewRec}>
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
            <Row icon="people-outline" label="Manage the crew" sublabel="Friends, search, invites" onPress={() => navigation.navigate('Friends')} />
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
    emptyCrew: { color: colors.muted, fontSize: font.small, lineHeight: 19, fontFamily: fonts.body },
    crewRow: {
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
    crewRowMe: { backgroundColor: withAlpha(colors.accent, 0.06), borderColor: withAlpha(colors.accent, 0.45) },
    crewName: { color: colors.text, fontSize: 13, fontFamily: fonts.bodyBold },
    crewSub: { color: colors.muted, fontSize: 10, marginTop: 1, fontFamily: fonts.body },
    crewRec: { color: colors.text, fontFamily: fonts.heroUpright, fontSize: 15 },
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
