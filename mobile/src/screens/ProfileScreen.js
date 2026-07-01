import { useCallback, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getMyStats, getAchievements } from '../api/me';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, Avatar, Button } from '../components/ui';

function Row({ icon, label, sublabel, onPress, danger }) {
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
      <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
    </Pressable>
  );
}

export default function ProfileScreen({ navigation }) {
  const { user, token, signOut } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [stats, setStats] = useState(null);
  const [trophies, setTrophies] = useState([]);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      getMyStats(token)
        .then((s) => active && setStats(s))
        .catch(() => {});
      getAchievements(token)
        .then((r) => active && setTrophies(r.achievements || []))
        .catch(() => {});
      return () => {
        active = false;
      };
    }, [token])
  );

  function howToPlay() {
    Alert.alert(
      'How to play',
      'Challenge a friend to a 1-on-1 fantasy duel: agree on the sport, lineup and scoring, draft your roster live (snake order, ticking clock), then the winner is declared automatically once the games finish.'
    );
  }

  const rec = stats?.record;
  const h2h = stats?.head_to_head || [];

  return (
    <Screen scroll>
      <Card style={styles.headerCard}>
        <Avatar name={user?.username || '?'} size={72} />
        <Text style={styles.username}>{user?.username}</Text>
        {user?.email ? <Text style={styles.email}>{user.email}</Text> : null}
      </Card>

      {/* Record */}
      <Card style={{ marginTop: spacing.lg }}>
        <View style={styles.recHead}>
          <Text style={styles.recTitle}>Record</Text>
          {rec?.streak?.count > 0 ? (
            <Text style={[styles.streakChip, { color: rec.streak.type === 'win' ? colors.accent : rec.streak.type === 'loss' ? colors.danger : colors.muted }]}>
              {rec.streak.type === 'win' ? '🔥 ' : ''}
              {rec.streak.type[0].toUpperCase()}
              {rec.streak.count}
            </Text>
          ) : null}
        </View>
        <View style={styles.recGrid}>
          <RecStat value={rec?.wins ?? 0} label="W" styles={styles} />
          <RecStat value={rec?.losses ?? 0} label="L" styles={styles} />
          <RecStat value={rec?.ties ?? 0} label="T" styles={styles} />
          <RecStat value={rec ? `${Math.round((rec.win_pct || 0) * 100)}%` : '—'} label="WIN" accent styles={styles} />
        </View>
        {rec?.played ? (
          <Text style={styles.recNote}>
            {rec.points_for} pts for · {rec.points_against} against over {rec.played} duels
          </Text>
        ) : (
          <Text style={styles.recNote}>No completed duels yet — go win one.</Text>
        )}
      </Card>

      {/* Head-to-head */}
      {h2h.length > 0 ? (
        <>
          <Text style={styles.sectionLabel}>Head to head</Text>
          <Card padded={false}>
            {h2h.map((r, i) => (
              <View key={r.opponent.id} style={[styles.h2hRow, i < h2h.length - 1 && styles.divider]}>
                <Avatar name={r.opponent.username} size={32} />
                <Text style={styles.h2hName}>{r.opponent.username}</Text>
                <Text style={styles.h2hRec}>
                  {r.wins}-{r.losses}
                  {r.ties ? `-${r.ties}` : ''}
                </Text>
              </View>
            ))}
          </Card>
        </>
      ) : null}

      {/* Trophies */}
      {trophies.length > 0 ? (
        <>
          <View style={styles.trophyHead}>
            <Text style={styles.sectionLabel}>Trophies</Text>
            <Text style={styles.trophyCount}>
              {trophies.filter((t) => t.earned).length}/{trophies.length}
            </Text>
          </View>
          <View style={styles.trophyGrid}>
            {trophies.map((t) => (
              <Trophy key={t.key} trophy={t} styles={styles} colors={colors} />
            ))}
          </View>
        </>
      ) : null}

      <Card padded={false} style={{ marginTop: spacing.lg }}>
        <Row icon="podium-outline" label="Leaderboard" sublabel="Standings among your friends" onPress={() => navigation.navigate('Leaderboard')} />
        <View style={styles.menuDivider} />
        <Row icon="settings-outline" label="Settings" sublabel="Appearance, preferences, account" onPress={() => navigation.navigate('Settings')} />
        <View style={styles.menuDivider} />
        <Row icon="help-circle-outline" label="How to play" onPress={howToPlay} />
      </Card>

      <View style={{ marginTop: spacing.xl }}>
        <Button title="Log Out" variant="danger" icon="log-out-outline" onPress={signOut} />
      </View>
    </Screen>
  );
}

function RecStat({ value, label, accent, styles }) {
  return (
    <View style={styles.recStat}>
      <Text style={[styles.recValue, accent && styles.recAccent]}>{value}</Text>
      <Text style={styles.recLabel}>{label}</Text>
    </View>
  );
}

function Trophy({ trophy, styles, colors }) {
  const earned = trophy.earned;
  return (
    <View style={styles.trophy}>
      <View style={[styles.trophyIcon, { backgroundColor: earned ? colors.accentSoft : colors.card, borderColor: earned ? colors.accentBorder : colors.borderSubtle }]}>
        <Ionicons name={trophy.icon} size={24} color={earned ? colors.accent : colors.placeholder} />
      </View>
      <Text style={[styles.trophyTitle, !earned && { color: colors.muted }]} numberOfLines={1}>
        {trophy.title}
      </Text>
      <Text style={styles.trophySub} numberOfLines={1}>
        {earned ? '✓ Earned' : `${Math.min(trophy.value, trophy.threshold)}/${trophy.threshold}`}
      </Text>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerCard: { alignItems: 'center', paddingVertical: spacing.xl },
    username: { color: colors.text, fontSize: font.title, fontWeight: '800', marginTop: spacing.md },
    email: { color: colors.muted, fontSize: font.body, marginTop: 2 },
    recHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.md },
    recTitle: { color: colors.text, fontSize: font.bodyLg, fontWeight: '700' },
    streakChip: { fontSize: font.body, fontWeight: '800' },
    recGrid: { flexDirection: 'row', justifyContent: 'space-between' },
    recStat: { alignItems: 'center', flex: 1 },
    recValue: { color: colors.text, fontSize: font.title, fontWeight: '900' },
    recAccent: { color: colors.accent },
    recLabel: { color: colors.muted, fontSize: 10, fontWeight: '800', letterSpacing: 0.5, marginTop: 2 },
    recNote: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.md },
    sectionLabel: { color: colors.muted, fontSize: font.caption, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 1, marginTop: spacing.lg, marginBottom: spacing.sm },
    trophyHead: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between' },
    trophyCount: { color: colors.accent, fontSize: font.small, fontWeight: '800' },
    trophyGrid: { flexDirection: 'row', flexWrap: 'wrap' },
    trophy: { width: '25%', alignItems: 'center', paddingVertical: spacing.sm },
    trophyIcon: { width: 52, height: 52, borderRadius: 26, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
    trophyTitle: { color: colors.text, fontSize: 11, fontWeight: '700', marginTop: 6, textAlign: 'center' },
    trophySub: { color: colors.placeholder, fontSize: 9, fontWeight: '700', marginTop: 1 },
    h2hRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: spacing.lg },
    h2hName: { color: colors.text, fontSize: font.body, fontWeight: '600', flex: 1, marginLeft: spacing.md },
    h2hRec: { color: colors.muted, fontSize: font.body, fontWeight: '800' },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    rowIcon: { width: 34, height: 34, borderRadius: 10, backgroundColor: colors.accentSoft, alignItems: 'center', justifyContent: 'center', marginRight: spacing.md },
    rowLabel: { color: colors.text, fontSize: font.bodyLg, fontWeight: '600' },
    rowSub: { color: colors.muted, fontSize: font.small, marginTop: 1 },
    menuDivider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle, marginLeft: 60 },
  });
