import { useCallback, useState } from 'react';
import { SectionList, StyleSheet, Text, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listDuels, getLiveResult } from '../api/duels';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Avatar, Button, Badge, EmptyState, SkeletonList, FadeIn } from '../components/ui';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };
const SPORT_TINT = { wnba: '#f59e0b', mlb: '#3b82f6', nba: '#ec4899', nfl: '#8b5cf6' };

// "Respond" only when it's genuinely YOUR move: a 1v1 challenge to you, or a
// group seat you haven't answered (an invitee who accepted is just waiting).
function needsMyResponse(d, uid) {
  if (d.status !== 'pending') return false;
  if (d.group) return (d.participants || []).some((p) => p.user?.id === uid && p.status === 'invited');
  return d.role === 'opponent';
}

function rowBadge(d, uid) {
  if (d.status === 'settled') {
    if (d.my_outcome === 'win') return { label: 'Won', tone: 'accent' };
    if (d.my_outcome === 'tie') return { label: 'Tie', tone: 'neutral' };
    return { label: 'Lost', tone: 'danger' };
  }
  switch (d.status) {
    case 'drafting':
      return { label: 'Drafting', tone: 'warning' };
    case 'drafted':
      return { label: 'Awaiting', tone: 'info' };
    case 'accepted':
      return { label: 'Ready', tone: 'accent' };
    case 'pending':
      return needsMyResponse(d, uid) ? { label: 'Respond', tone: 'info' } : { label: 'Pending', tone: 'neutral' };
    case 'declined':
      return { label: 'Declined', tone: 'danger' };
    case 'cancelled':
      return { label: 'Cancelled', tone: 'neutral' };
    case 'countered':
      return { label: 'Countered', tone: 'info' };
    default:
      return { label: d.status, tone: 'neutral' };
  }
}

function rowTitle(d) {
  if (!d.group) return `vs ${d.opponent?.username || 'Opponent'}`;
  if (d.role === 'challenger') return `Your ${d.party_size}-player match`;
  return `${d.opponent?.username || 'A friend'}'s ${d.party_size}-player match`;
}

function rowMeta(d) {
  const sport = SPORT_EMOJI[d.sport] || '🎯';
  if (d.group && d.status === 'pending') {
    const seated = (d.participants || []).filter((p) => p.status === 'accepted').length;
    return `${sport} ${seated}/${d.party_size} in · ${d.roster_size} rounds`;
  }
  return `${sport} ${d.roster_size} rounds`;
}

const ordinalShort = (n) => (n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`);

// The score line for an in-play duel, right in the list: "You 62.5 – 58.0
// buddy" (or "2nd · 51.0 pts" in a group), with a red dot while games are
// live. Polls the existing /live endpoint every 30s while the tab is open;
// once the duel settles (409) it quietly says so.
function LiveScoreInline({ token, duel, colors, styles }) {
  const [live, setLive] = useState(null);
  const [settled, setSettled] = useState(false);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
        try {
          const res = await getLiveResult(token, duel.id);
          if (active) setLive(res);
        } catch (e) {
          if (active) setSettled(true);
        }
      };
      tick();
      const iv = setInterval(tick, 30000);
      return () => {
        active = false;
        clearInterval(iv);
      };
    }, [token, duel.id])
  );

  if (settled && !live) return <Text style={styles.meta}>Awaiting final scores</Text>;
  if (!live) return <Text style={styles.meta}>{rowMeta(duel)}</Text>;

  const isLive = (live.games?.live || 0) > 0;
  let line = '';

  if (live.challenger) {
    const me = live.challenger.is_me ? live.challenger : live.opponent;
    const them = live.challenger.is_me ? live.opponent : live.challenger;
    line = `You ${(me.total ?? 0).toFixed(1)} – ${(them.total ?? 0).toFixed(1)} ${them.user.username}`;
  } else {
    const idx = (live.sides || []).findIndex((s) => s.is_me);
    const mine = live.sides?.[idx];
    line = mine ? `${ordinalShort(idx + 1)} of ${live.sides.length} · ${(mine.total ?? 0).toFixed(1)} pts` : rowMeta(duel);
  }

  return (
    <View style={styles.liveLine}>
      {isLive ? <View style={styles.liveDot} /> : null}
      <Text style={[styles.meta, { marginTop: 0 }, isLive && { color: colors.text, fontWeight: '600' }]} numberOfLines={1}>
        {line}
      </Text>
    </View>
  );
}

// Who's in this duel, as overlapping faces — you vs them, or the group stack.
function FacingAvatars({ duel, myName }) {
  const names = duel.group
    ? (duel.participants || []).filter((p) => p.status !== 'declined').slice(0, 4).map((p) => p.user?.username || '?')
    : [myName || 'You', duel.opponent?.username || '?'];

  return (
    <View style={{ flexDirection: 'row', marginRight: spacing.md }}>
      {names.map((n, i) => (
        <View key={`${n}-${i}`} style={{ marginLeft: i === 0 ? 0 : -10, zIndex: names.length - i }}>
          <Avatar name={n} size={30} />
        </View>
      ))}
    </View>
  );
}

const ACTIVE_STATES = ['pending', 'accepted', 'drafting', 'drafted', 'countered'];

function partition(duels) {
  const active = duels.filter((d) => ACTIVE_STATES.includes(d.status));
  const past = duels.filter((d) => !ACTIVE_STATES.includes(d.status));
  return { active, past };
}

function activeSections(active, uid) {
  const needsResponse = active.filter((d) => needsMyResponse(d, uid));
  const waiting = active.filter((d) => d.status === 'pending' && !needsMyResponse(d, uid));
  const inProgress = active.filter((d) => ['accepted', 'drafting', 'drafted', 'countered'].includes(d.status));
  return [
    { title: 'Needs your response', data: needsResponse },
    { title: 'Waiting on them', data: waiting },
    { title: 'In progress', data: inProgress },
  ];
}

function pastSections(past) {
  const completed = past.filter((d) => d.status === 'settled');
  const other = past.filter((d) => d.status !== 'settled');
  return [
    { title: 'Completed', data: completed },
    { title: 'Declined & cancelled', data: other },
  ];
}

export default function DuelsListScreen({ navigation }) {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duels, setDuels] = useState([]);
  const [tab, setTab] = useState('active');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listDuels(token);
      setDuels(res.duels);
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

  const { active, past } = partition(duels);
  const sections = tab === 'active' ? activeSections(active, user?.id) : pastSections(past);

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <Button title="New Challenge" icon="add" onPress={() => navigation.navigate('CreateChallenge')} />

        <View style={styles.segment}>
          <SegTab label="Active" count={active.length} on={tab === 'active'} onPress={() => setTab('active')} styles={styles} colors={colors} />
          <SegTab label="Past" count={past.length} on={tab === 'past'} onPress={() => setTab('past')} styles={styles} colors={colors} />
        </View>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <SkeletonList count={5} />
        ) : (
          <SectionList
            sections={sections}
            keyExtractor={(item) => String(item.id)}
            stickySectionHeadersEnabled={false}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={{ paddingBottom: spacing.xl, flexGrow: 1 }}
            ListEmptyComponent={
              tab === 'active' ? (
                <EmptyState
                  icon="flame-outline"
                  title="Nothing on the line"
                  subtitle="Somebody out there thinks they can beat you. Set the terms."
                  action={<Button title="New Challenge" icon="add" onPress={() => navigation.navigate('CreateChallenge')} />}
                />
              ) : (
                <EmptyState icon="time-outline" title="No history yet" subtitle="Finished duels land here — the wins, the losses, and the receipts." />
              )
            }
            renderSectionHeader={({ section }) => (section.data.length ? <Text style={styles.sectionHeader}>{section.title}</Text> : null)}
            renderItem={({ item, index }) => {
              const badge = rowBadge(item, user?.id);
              return (
                <FadeIn index={index}>
                  <Pressable
                    onPress={() => navigation.navigate('DuelDetail', { id: item.id })}
                    style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.card }]}
                  >
                    <View style={[styles.sportBar, { backgroundColor: SPORT_TINT[item.sport] || colors.border }]} />
                    <FacingAvatars duel={item} myName={user?.username} />
                    <View style={{ flex: 1 }}>
                      <Text style={styles.vs} numberOfLines={1}>
                        {rowTitle(item)}
                      </Text>
                      {item.status === 'drafted' ? (
                        <LiveScoreInline token={token} duel={item} colors={colors} styles={styles} />
                      ) : (
                        <Text style={styles.meta}>{rowMeta(item)}</Text>
                      )}
                    </View>
                    <Badge label={badge.label} tone={badge.tone} />
                    <Ionicons name="chevron-forward" size={18} color={colors.placeholder} style={{ marginLeft: spacing.sm }} />
                  </Pressable>
                </FadeIn>
              );
            }}
          />
        )}
      </View>
    </Screen>
  );
}

function SegTab({ label, count, on, onPress, styles, colors }) {
  return (
    <Pressable onPress={onPress} style={[styles.segTab, on && styles.segTabOn]}>
      <Text style={[styles.segLabel, { color: on ? colors.onAccent : colors.muted }]}>
        {label}
        {count > 0 ? `  ${count}` : ''}
      </Text>
    </Pressable>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    segment: { flexDirection: 'row', gap: spacing.xs, backgroundColor: colors.card, borderRadius: radius.md, padding: spacing.xs, marginTop: spacing.md, borderWidth: 1, borderColor: colors.borderSubtle },
    segTab: { flex: 1, alignItems: 'center', paddingVertical: 10, borderRadius: radius.sm },
    segTabOn: { backgroundColor: colors.accent },
    segLabel: { fontSize: font.body, fontWeight: '700' },
    sectionHeader: {
      color: colors.muted,
      fontSize: font.caption,
      fontWeight: '800',
      textTransform: 'uppercase',
      letterSpacing: 1,
      marginTop: spacing.lg,
      marginBottom: spacing.xs,
    },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: spacing.sm, borderRadius: radius.md },
    sportBar: { width: 3, height: 34, borderRadius: 2, marginRight: spacing.md },
    vs: { color: colors.text, fontSize: font.subtitle, fontWeight: '700' },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    liveLine: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 },
    liveDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.danger },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
