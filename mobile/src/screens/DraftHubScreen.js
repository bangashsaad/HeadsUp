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
