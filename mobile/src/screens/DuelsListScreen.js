import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View, Pressable, RefreshControl, Alert } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { listDuels, getLiveResult, respondToDuel, rematch } from '../api/duels';
import { setDraftLive } from '../state/attention';
import { impact } from '../haptics';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, Button, Badge, EmptyState, SkeletonList, FadeIn, Segmented, CondTitle, Kicker, BlinkDot } from '../components/ui';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

// "Respond" only when it's genuinely YOUR move: a 1v1 challenge to you, or a
// group seat you haven't answered (an invitee who accepted is just waiting).
function needsMyResponse(d, uid) {
  if (d.status !== 'pending') return false;
  if (d.group) return (d.participants || []).some((p) => p.user?.id === uid && p.status === 'invited');
  return d.role === 'opponent';
}

function rowTitle(d) {
  if (!d.group) return d.opponent?.username || 'Opponent';
  if (d.role === 'challenger') return `Your ${d.party_size}-player match`;
  return `${d.opponent?.username || 'A friend'}'s ${d.party_size}-player match`;
}

function rowMeta(d) {
  const sport = SPORT_EMOJI[d.sport] || '🎯';
  const pot = d.stake_coins > 0 ? ` · ◎ ${d.pot_coins || d.stake_coins * 2} pot` : '';
  if (d.group && d.status === 'pending') {
    const seated = (d.participants || []).filter((p) => p.status === 'accepted').length;
    return `${sport} ${String(d.sport || '').toUpperCase()} · ${seated}/${d.party_size} in · ${d.roster_size} rounds${pot}`;
  }
  return `${sport} ${String(d.sport || '').toUpperCase()} · ${d.group ? `${d.party_size}-way` : 'snake'} · ${d.roster_size} slots${pot}`;
}

// The receipt line's coin swing: only 1v1 duels are derivable client-side
// (group tie splits live on the result payload instead).
function coinDelta(d) {
  if (!d.stake_coins || d.group) return null;
  if (d.my_outcome === 'win') return `+${d.stake_coins}`;
  if (d.my_outcome === 'loss') return `−${d.stake_coins}`;
  return null;
}

function fmtDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

// Who's in this duel, as overlapping tiles — the opponent, or the group stack.
function Faces({ duel, myName, size = 34 }) {
  const names = duel.group
    ? (duel.participants || []).filter((p) => p.status !== 'declined').slice(0, 4).map((p) => p.user?.username || '?')
    : [duel.opponent?.username || '?'];
  return (
    <View style={{ flexDirection: 'row' }}>
      {names.map((n, i) => (
        <View key={`${n}-${i}`} style={{ marginLeft: i === 0 ? 0 : -10, zIndex: names.length - i }}>
          <Avatar name={n} size={size} />
        </View>
      ))}
    </View>
  );
}

// An in-play duel row: live totals, a momentum sliver, tap for the matchup.
function LiveRow({ token, duel, myName, onOpen, colors, styles }) {
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

  let me = null;
  let them = null;
  if (live?.challenger) {
    const mine = live.challenger.is_me ? live.challenger : live.opponent;
    const theirs = live.challenger.is_me ? live.opponent : live.challenger;
    me = mine?.total ?? 0;
    them = theirs?.total ?? 0;
  } else if (live?.sides) {
    const mine = live.sides.find((s) => s.is_me);
    const best = live.sides.find((s) => !s.is_me);
    me = mine?.total ?? 0;
    them = best?.total ?? 0;
  }

  const gamesLive = (live?.games?.live || 0) > 0;
  const pct = me == null || me + them <= 0 ? 0.5 : Math.max(0.08, Math.min(0.92, me / (me + them)));
  const status =
    me == null ? (settled ? 'AWAITING FINAL' : 'SYNCING…') : me > them ? 'YOU LEAD' : me < them ? 'CHASING' : 'TIED';

  return (
    <Pressable onPress={onOpen} style={({ pressed }) => [styles.rowCard, pressed && { transform: [{ scale: 0.98 }] }]}>
      <View style={styles.rowInner}>
        <Faces duel={duel} myName={myName} />
        <View style={{ flex: 1, marginLeft: spacing.sm }}>
          <Text style={styles.rowName}>{rowTitle(duel)}</Text>
          <View style={styles.liveLine}>
            {gamesLive ? <BlinkDot color={colors.danger} size={5} period={1400} /> : null}
            <Text style={styles.liveScore}>{me == null ? rowMeta(duel) : `${me.toFixed(1)} – ${them.toFixed(1)}`}</Text>
            <Text style={[styles.liveTag, { color: me != null && me >= them ? colors.accent : colors.muted }]}>{status}</Text>
          </View>
        </View>
        <View style={styles.momTrack}>
          <LinearGradient
            colors={[colors.accent, colors.purple]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 0 }}
            style={{ width: `${Math.round(pct * 100)}%`, height: '100%' }}
          />
        </View>
      </View>
    </Pressable>
  );
}

export default function DuelsListScreen({ navigation }) {
  const { token, user, refreshUser } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duels, setDuels] = useState([]);
  const [tab, setTab] = useState('active');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listDuels(token);
      setDuels(res.duels);
      setError(null);
      setDraftLive((res.duels || []).some((d) => d.status === 'drafting'));
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const ACTIVE_STATES = ['pending', 'accepted', 'drafting', 'drafted', 'countered'];
  const active = duels.filter((d) => ACTIVE_STATES.includes(d.status));
  const past = duels.filter((d) => !ACTIVE_STATES.includes(d.status));

  const drafting = active.filter((d) => d.status === 'drafting');
  const inPlay = active.filter((d) => d.status === 'drafted');
  const respond = active.filter((d) => needsMyResponse(d, user?.id));
  const countered = active.filter((d) => d.status === 'countered');
  const ready = active.filter((d) => d.status === 'accepted');
  const waiting = active.filter((d) => d.status === 'pending' && !needsMyResponse(d, user?.id));
  const settled = past.filter((d) => d.status === 'settled');
  const dead = past.filter((d) => d.status !== 'settled');

  function openDetail(d) {
    navigation.navigate('DuelDetail', { id: d.id });
  }
  function openDraft(d) {
    navigation.navigate('DraftRoom', { id: d.id, opponentName: d.opponent?.username });
  }
  function openLive(d) {
    navigation.navigate('LiveMatchup', { id: d.id, opponentName: d.opponent?.username });
  }

  async function act(d, action) {
    setBusyId(d.id);
    impact();
    try {
      await respondToDuel(token, d.id, action);
      refreshUser(); // stake/refund just moved
      await load();
    } catch (e) {
      Alert.alert('That didn’t stick', e.message);
    } finally {
      setBusyId(null);
    }
  }

  async function runItBack(d) {
    setBusyId(d.id);
    impact();
    try {
      const res = await rematch(token, d.id);
      refreshUser(); // the copied stake just left the wallet
      await load();
      const newId = res?.duel?.id;
      if (newId) navigation.navigate('DuelDetail', { id: newId });
    } catch (e) {
      Alert.alert('No rematch (yet)', e.message);
    } finally {
      setBusyId(null);
    }
  }

  return (
    <Screen padded={false} edges={['top']}>
      <View style={styles.header}>
        <CondTitle size={26} style={{ paddingRight: 4 }}>
          DUELS
        </CondTitle>
        <Button title="+ New challenge" size="sm" full={false} onPress={() => navigation.navigate('CreateChallenge')} />
      </View>
      <Segmented
        style={{ marginHorizontal: spacing.lg, marginTop: spacing.md }}
        value={tab}
        onChange={setTab}
        options={[
          { key: 'active', label: 'Active', count: active.length },
          { key: 'past', label: 'Past', count: past.length },
        ]}
      />

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading ? (
        <View style={{ padding: spacing.lg }}>
          <SkeletonList count={5} />
        </View>
      ) : (
        <ScrollView
          contentContainerStyle={{ padding: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.xxl, gap: 10, flexGrow: 1 }}
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor={colors.accent} />
          }
        >
          {tab === 'active' ? (
            active.length === 0 ? (
              <EmptyState
                icon="flame-outline"
                title="Nothing on the line"
                subtitle="Somebody out there thinks they can beat you. Set the terms."
                action={<Button title="New challenge" onPress={() => navigation.navigate('CreateChallenge')} />}
              />
            ) : (
              <>
                {drafting.map((d, i) => (
                  <FadeIn key={d.id} index={i}>
                    <Pressable onPress={() => openDraft(d)} style={({ pressed }) => [pressed && { transform: [{ scale: 0.98 }] }]}>
                      <LinearGradient
                        colors={[withAlpha(colors.danger, 0.12), colors.card]}
                        start={{ x: 0, y: 0 }}
                        end={{ x: 0.9, y: 1 }}
                        style={[styles.rowCard, { borderColor: colors.dangerBorder }]}
                      >
                        <View style={styles.rowInner}>
                          <Faces duel={d} myName={user?.username} />
                          <View style={{ flex: 1, marginLeft: spacing.sm }}>
                            <Text style={styles.rowName}>{rowTitle(d)}</Text>
                            <Text style={styles.rowMeta}>{rowMeta(d)}</Text>
                          </View>
                          <Badge label="Drafting" tone="danger" blink />
                        </View>
                      </LinearGradient>
                    </Pressable>
                  </FadeIn>
                ))}

                {inPlay.map((d, i) => (
                  <FadeIn key={d.id} index={drafting.length + i}>
                    <LiveRow token={token} duel={d} myName={user?.username} onOpen={() => openLive(d)} colors={colors} styles={styles} />
                  </FadeIn>
                ))}

                {respond.map((d, i) => (
                  <FadeIn key={d.id} index={drafting.length + inPlay.length + i}>
                    <View style={styles.rowCard}>
                      <Pressable onPress={() => openDetail(d)} style={styles.rowInner}>
                        <Faces duel={d} myName={user?.username} />
                        <View style={{ flex: 1, marginLeft: spacing.sm }}>
                          <Text style={styles.rowName}>{rowTitle(d)}</Text>
                          <Text style={styles.rowMeta}>
                            {rowMeta(d)} · {d.group ? "you're invited" : 'they set the terms'}
                          </Text>
                        </View>
                        <Badge label="Respond" tone="info" />
                      </Pressable>
                      <View style={styles.respondRow}>
                        <Pressable
                          disabled={busyId === d.id}
                          onPress={() => act(d, 'accept')}
                          style={({ pressed }) => [styles.acceptBtn, pressed && { opacity: 0.85 }]}
                        >
                          <Text style={styles.acceptText}>ACCEPT</Text>
                        </Pressable>
                        {!d.group ? (
                          <Pressable
                            disabled={busyId === d.id}
                            onPress={() =>
                              navigation.navigate('Counter', {
                                id: d.id,
                                initial: { sport: d.sport, lineup_template: d.lineup_template, pick_clock_seconds: d.pick_clock_seconds },
                              })
                            }
                            style={({ pressed }) => [styles.counterBtn, pressed && { opacity: 0.85 }]}
                          >
                            <Text style={styles.counterText}>COUNTER</Text>
                          </Pressable>
                        ) : null}
                        <Pressable
                          disabled={busyId === d.id}
                          onPress={() => act(d, 'decline')}
                          style={({ pressed }) => [styles.declineBtn, pressed && { opacity: 0.85 }]}
                        >
                          <Text style={styles.declineText}>DECLINE</Text>
                        </Pressable>
                      </View>
                    </View>
                  </FadeIn>
                ))}

                {countered.map((d) => (
                  <Pressable key={d.id} onPress={() => openDetail(d)} style={({ pressed }) => [styles.rowCard, pressed && { opacity: 0.85 }]}>
                    <View style={styles.rowInner}>
                      <Faces duel={d} myName={user?.username} />
                      <View style={{ flex: 1, marginLeft: spacing.sm }}>
                        <Text style={styles.rowName}>{rowTitle(d)}</Text>
                        <Text style={styles.rowMeta}>{rowMeta(d)} · terms changed</Text>
                      </View>
                      <Badge label="Countered" tone="info" />
                    </View>
                  </Pressable>
                ))}

                {ready.map((d) => (
                  <Pressable key={d.id} onPress={() => openDraft(d)} style={({ pressed }) => [styles.rowCard, pressed && { transform: [{ scale: 0.98 }] }]}>
                    <View style={styles.rowInner}>
                      <Faces duel={d} myName={user?.username} />
                      <View style={{ flex: 1, marginLeft: spacing.sm }}>
                        <Text style={styles.rowName}>{rowTitle(d)}</Text>
                        <Text style={styles.rowMeta}>{rowMeta(d)} · room is open</Text>
                      </View>
                      <Badge label="Ready" tone="accent" />
                    </View>
                  </Pressable>
                ))}

                {waiting.length > 0 ? (
                  <Kicker size={9} tracking={2} style={{ marginTop: spacing.sm, marginLeft: 2 }}>
                    Waiting on them
                  </Kicker>
                ) : null}
                {waiting.map((d) => (
                  <Pressable
                    key={d.id}
                    onPress={() => openDetail(d)}
                    style={({ pressed }) => [styles.rowCard, { opacity: 0.75 }, pressed && { opacity: 0.6 }]}
                  >
                    <View style={styles.rowInner}>
                      <Faces duel={d} myName={user?.username} />
                      <View style={{ flex: 1, marginLeft: spacing.sm }}>
                        <Text style={styles.rowName}>{rowTitle(d)}</Text>
                        <Text style={styles.rowMeta}>{rowMeta(d)} · waiting on {d.group ? 'the group' : 'them'}</Text>
                      </View>
                      <Badge label="Sent" tone="neutral" />
                    </View>
                  </Pressable>
                ))}
              </>
            )
          ) : past.length === 0 ? (
            <EmptyState
              icon="time-outline"
              title="No history yet"
              subtitle="Finished duels land here — the wins, the losses, and the receipts."
            />
          ) : (
            <>
              {settled.map((d, i) => {
                const won = d.my_outcome === 'win';
                const tie = d.my_outcome === 'tie';
                const tint = won ? colors.accent : tie ? colors.muted : colors.danger;
                return (
                  <FadeIn key={d.id} index={i}>
                    <View style={[styles.receiptRow, { borderLeftColor: tint }]}>
                      <Pressable
                        onPress={() => navigation.navigate('Results', { id: d.id, opponentName: d.opponent?.username })}
                        style={{ flexDirection: 'row', alignItems: 'center', flex: 1, gap: 11 }}
                      >
                        <CondTitle size={18} color={tint} style={{ width: 26 }}>
                          {won ? 'W' : tie ? 'T' : 'L'}
                        </CondTitle>
                        <View style={{ flex: 1 }}>
                          <Text style={styles.rowName}>vs {rowTitle(d)}</Text>
                          <Text style={styles.rowMeta}>
                            {SPORT_EMOJI[d.sport] || '🎯'} {String(d.sport || '').toUpperCase()}
                            {d.settled_at ? ` · ${fmtDate(d.settled_at)}` : ''}
                          </Text>
                        </View>
                        {coinDelta(d) ? (
                          <Text style={[styles.coinSwing, { color: won ? colors.gold : colors.muted }]}>◎ {coinDelta(d)}</Text>
                        ) : null}
                      </Pressable>
                      {!d.group ? (
                        <Pressable
                          disabled={busyId === d.id}
                          onPress={() => runItBack(d)}
                          style={({ pressed }) => [styles.rematchBtn, pressed && { opacity: 0.8 }]}
                        >
                          <Text style={styles.rematchText}>REMATCH</Text>
                        </Pressable>
                      ) : null}
                    </View>
                  </FadeIn>
                );
              })}

              {dead.length > 0 ? (
                <Kicker size={9} tracking={2} style={{ marginTop: spacing.sm, marginLeft: 2 }}>
                  Declined & cancelled
                </Kicker>
              ) : null}
              {dead.map((d) => (
                <Pressable
                  key={d.id}
                  onPress={() => openDetail(d)}
                  style={({ pressed }) => [styles.rowCard, { opacity: 0.6 }, pressed && { opacity: 0.45 }]}
                >
                  <View style={styles.rowInner}>
                    <Faces duel={d} myName={user?.username} />
                    <View style={{ flex: 1, marginLeft: spacing.sm }}>
                      <Text style={styles.rowName}>{rowTitle(d)}</Text>
                      <Text style={styles.rowMeta}>{rowMeta(d)}</Text>
                    </View>
                    <Badge label={d.status} tone="neutral" />
                  </View>
                </Pressable>
              ))}
            </>
          )}
        </ScrollView>
      )}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: spacing.lg,
      paddingTop: spacing.sm,
    },
    rowCard: {
      borderRadius: 14,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      padding: 13,
      overflow: 'hidden',
    },
    rowInner: { flexDirection: 'row', alignItems: 'center' },
    rowName: { fontSize: 14, fontFamily: fonts.bodyExtra, color: colors.text },
    rowMeta: { fontSize: 10.5, color: colors.muted, fontFamily: fonts.bodySemi, marginTop: 2 },
    liveLine: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 },
    liveScore: { fontFamily: fonts.condBold, fontSize: 13, color: colors.text },
    liveTag: { fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 0.5 },
    momTrack: { width: 56, height: 5, borderRadius: 3, backgroundColor: colors.border, overflow: 'hidden', marginLeft: spacing.sm },
    respondRow: { flexDirection: 'row', gap: 7, marginTop: 11 },
    acceptBtn: {
      flex: 1,
      backgroundColor: colors.accent,
      borderRadius: 9,
      paddingVertical: 8,
      alignItems: 'center',
    },
    acceptText: { color: colors.onAccent, fontFamily: fonts.heroUpright, fontSize: 14, letterSpacing: 1 },
    counterBtn: {
      flex: 1,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 9,
      paddingVertical: 8,
      alignItems: 'center',
    },
    counterText: { color: colors.text, fontFamily: fonts.heroUpright, fontSize: 14, letterSpacing: 1 },
    declineBtn: {
      flex: 1,
      borderWidth: 1,
      borderColor: withAlpha(colors.danger, 0.4),
      borderRadius: 9,
      paddingVertical: 8,
      alignItems: 'center',
    },
    declineText: { color: colors.danger, fontFamily: fonts.heroUpright, fontSize: 14, letterSpacing: 1 },
    receiptRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 11,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderLeftWidth: 3,
      borderRadius: 12,
      paddingVertical: 12,
      paddingHorizontal: 13,
    },
    rematchBtn: {
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingVertical: 4,
      paddingHorizontal: 11,
    },
    rematchText: { color: colors.muted, fontSize: 10, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    coinSwing: { fontSize: 13, fontFamily: fonts.condBold, letterSpacing: 0.5 },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
