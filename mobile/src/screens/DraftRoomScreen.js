import { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Easing, FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { connectDraft } from '../api/socket';
import { impact, notify, ImpactStyle, NotifyType } from '../haptics';
import PickClock from '../components/PickClock';
import LineupSlots from '../components/LineupSlots';
import DraftTicker from '../components/DraftTicker';
import DraftOrderDots from '../components/DraftOrderDots';
import RosterSheet from '../components/RosterSheet';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Avatar, Button, Chip, SearchInput, EmptyState } from '../components/ui';
import { shortName } from '../utils/names';

// "7:00 PM ET" for a game today (ET), "Tmw 7:00 PM ET" for tomorrow — so you
// know WHEN a player plays before you draft them. ET = UTC-4 in season.
function nextGameLabel(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d)) return null;
  const et = new Date(d.getTime() - 4 * 3600 * 1000);
  const nowEt = new Date(Date.now() - 4 * 3600 * 1000);
  const sameDay = et.getUTCDate() === nowEt.getUTCDate() && et.getUTCMonth() === nowEt.getUTCMonth();
  let h = et.getUTCHours();
  const m = et.getUTCMinutes();
  const ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${sameDay ? '' : 'Tmw '}${h}:${String(m).padStart(2, '0')} ${ap} ET`;
}

export default function DraftRoomScreen({ route, navigation }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token, user } = useAuth();
  const myId = user.id;
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [state, setState] = useState(null);
  const [error, setError] = useState(null);
  const connRef = useRef(null);

  useEffect(() => {
    const conn = connectDraft(id, token, {
      onJoin: (reply) => setState(reply.state),
      onUpdate: (payload) => setState(payload.state),
      onError: () => setError('Could not join the draft room.'),
    });
    connRef.current = conn;
    return () => conn.leave();
  }, [id, token]);

  if (!state) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.accent} />
        <Text style={styles.dim}>{error || 'Connecting to the draft…'}</Text>
      </View>
    );
  }

  if (state.phase === 'cancelled') {
    return (
      <View style={styles.center}>
        <EmptyState icon="close-circle-outline" title="Draft cancelled" subtitle="No winner — nobody drafted. You can set up a new challenge." />
      </View>
    );
  }

  if (state.phase === 'lobby') {
    return <Lobby state={state} myId={myId} opponentName={opponentName} conn={connRef.current} />;
  }

  return (
    <DraftBoard
      state={state}
      myId={myId}
      duelId={id}
      opponentName={opponentName}
      conn={connRef.current}
      error={error}
      setError={setError}
      navigation={navigation}
    />
  );
}

function Lobby({ state, myId, opponentName, conn }) {
  const styles = useThemedStyles(makeStyles);
  const players =
    state.players && state.players.length > 0
      ? state.players
      : Object.keys(state.ready || {}).map((id) => ({ id, username: opponentName }));
  const iAmReady = state.ready[String(myId)] || state.ready[myId];

  return (
    <View style={styles.lobby}>
      <Text style={styles.lobbyTitle}>Draft Lobby</Text>
      <Text style={styles.dim}>
        {players.length > 2 ? `All ${players.length} players must be ready to start.` : 'Both players must be ready to start.'}
      </Text>

      <View style={styles.readyRow}>
        {players.map((p) => {
          const isMe = String(p.id) === String(myId);
          return <ReadyPill key={p.id} name={isMe ? 'You' : p.username} ready={state.ready[p.id]} />;
        })}
      </View>

      <Button
        title={iAmReady ? 'Ready — waiting…' : "I'm Ready"}
        icon={iAmReady ? 'checkmark-circle' : 'flame'}
        onPress={() => conn?.ready()}
        disabled={iAmReady}
      />
      <Button title="Cancel draft (no-show)" variant="ghost" onPress={() => conn?.cancel()} style={{ marginTop: spacing.sm }} />
    </View>
  );
}

// A slot in the flow-layout strip; flashes in the drafter's color on fill.
function FlashSlotCard({ slot, pick, tint, styles, colors }) {
  const flash = useRef(new Animated.Value(0)).current;
  const prevId = useRef(pick?.player?.id);

  useEffect(() => {
    const id = pick?.player?.id;
    if (id && prevId.current !== id) {
      flash.setValue(1);
      Animated.timing(flash, { toValue: 0, duration: 900, useNativeDriver: true }).start();
    }
    prevId.current = id;
  }, [pick?.player?.id, flash]);

  return (
    <View style={[styles.slotCard, pick && styles.slotCardFilled]}>
      <Animated.View
        pointerEvents="none"
        style={[
          StyleSheet.absoluteFillObject,
          { backgroundColor: tint, borderRadius: radius.md, opacity: flash.interpolate({ inputRange: [0, 1], outputRange: [0, 0.35] }) },
        ]}
      />
      <Text style={styles.slotCardLabel}>{slot.label}</Text>
      <Text style={[styles.slotCardName, !pick && { color: colors.placeholder }]} numberOfLines={1}>
        {pick ? shortName(pick.player.name) : '—'}
      </Text>
    </View>
  );
}

function ReadyPill({ name, ready }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  return (
    <View style={[styles.pill, ready ? styles.pillOn : styles.pillOff]}>
      <Avatar name={name} size={44} />
      <Text style={styles.pillName} numberOfLines={1}>
        {name}
      </Text>
      <View style={styles.pillStateRow}>
        <Ionicons name={ready ? 'checkmark-circle' : 'ellipse-outline'} size={15} color={ready ? colors.accent : colors.muted} />
        <Text style={[styles.pillState, ready && { color: colors.accent }]}>{ready ? 'Ready' : 'Not ready'}</Text>
      </View>
    </View>
  );
}

function DraftBoard({ state, myId, duelId, opponentName, conn, error, setError, navigation }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const complete = state.phase === 'complete';
  const isMyTurn = String(state.current_picker_id) === String(myId);

  const players = state.players || [];
  const flow = players.length > 2; // 3-4 players: flow layout (strip + seat tabs)

  const myPicks = useMemo(() => state.picks.filter((p) => String(p.user_id) === String(myId)), [state.picks, myId]);
  const oppPicks = useMemo(() => state.picks.filter((p) => String(p.user_id) !== String(myId)), [state.picks, myId]);
  const picksFor = (uid) => state.picks.filter((p) => String(p.user_id) === String(uid));

  const oppId = useMemo(
    () =>
      players.find((p) => String(p.id) !== String(myId))?.id ??
      Object.keys(state.ready || {}).find((u) => String(u) !== String(myId)),
    [players, state.ready, myId]
  );

  // The server ships the full snake once the order is drawn; fall back to
  // deriving the 2-player snake from first_picker_id for older payloads.
  const order = useMemo(() => {
    if (state.pick_order && state.pick_order.length > 0) return state.pick_order;
    const first = state.first_picker_id;
    if (!first) return [];
    const other = Object.keys(state.ready || {}).find((u) => String(u) !== String(first)) ?? first;
    const out = [];
    for (let r = 1; r <= state.slots.length; r++) {
      if (r % 2 === 1) out.push(first, other);
      else out.push(other, first);
    }
    return out;
  }, [state.pick_order, state.first_picker_id, state.ready, state.slots.length]);

  const nameFor = (uid) => {
    if (String(uid) === String(myId)) return 'You';
    const p = players.find((x) => String(x.id) === String(uid));
    return p ? p.username : opponentName;
  };

  // One UNIQUE color per seat (name-hash tints can collide — two players both
  // green was unreadable). You are always accent green; everyone else gets a
  // distinct non-green tint in seat order. Seat tabs carry the same dot so the
  // order strip is decodable.
  const seatTint = useMemo(() => {
    const tints = ['#3b82f6', '#f59e0b', '#ec4899', '#8b5cf6', '#06b6d4', '#f97316'];
    const map = {};
    let i = 0;
    const ids = players.length > 0 ? players.map((p) => p.id) : Object.keys(state.ready || {});
    for (const id of ids) {
      if (String(id) === String(myId)) map[String(id)] = colors.accent;
      else map[String(id)] = tints[i++ % tints.length];
    }
    return map;
  }, [players, state.ready, myId, colors.accent]);

  const colorFor = (uid) => seatTint[String(uid)] || colors.muted;
  const [sheetUid, setSheetUid] = useState(null); // user id whose roster sheet is open

  const eligible = useMemo(() => {
    const filled = new Set(myPicks.map((p) => p.slot));
    const open = state.slots.filter((s) => !filled.has(s.key));
    return new Set(open.flatMap((s) => s.eligible));
  }, [state.slots, myPicks]);

  const [query, setQuery] = useState('');
  const [posFilter, setPosFilter] = useState(null);
  const [queue, setQueue] = useState([]);
  const queued = useMemo(() => new Set(queue), [queue]);

  // Keep the server's private auto-pick order in sync with the local queue.
  useEffect(() => {
    conn?.setQueue?.(queue);
  }, [queue, conn]);

  // Drop drafted players from the queue as they leave the pool.
  useEffect(() => {
    const availIds = new Set(state.available.map((p) => p.id));
    setQueue((q) => {
      const pruned = q.filter((pid) => availIds.has(pid));
      return pruned.length === q.length ? q : pruned;
    });
  }, [state.available]);

  function toggleQueue(pid) {
    impact(ImpactStyle.Light);
    setQueue((q) => (q.includes(pid) ? q.filter((x) => x !== pid) : [...q, pid]));
  }

  const prevTurn = useRef(false);
  useEffect(() => {
    if (isMyTurn && !prevTurn.current && !complete) notify(NotifyType.Success);
    prevTurn.current = isMyTurn;
  }, [isMyTurn, complete]);

  // The status bar breathes in the current picker's color — a slow pulse when
  // someone else is up, an insistent one when it's you.
  const pulse = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (complete || !state.current_picker_id) {
      pulse.setValue(0);
      return;
    }
    const dur = isMyTurn ? 600 : 1200;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 1, duration: dur, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0, duration: dur, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [isMyTurn, complete, state.current_picker_id, pulse]);

  const lineupFull = !complete && eligible.size === 0;

  const positions = useMemo(() => {
    const set = new Set(state.available.filter((p) => lineupFull || eligible.has(p.position)).map((p) => p.position));
    return Array.from(set).sort();
  }, [state.available, eligible, lineupFull]);

  const activePos = posFilter && positions.includes(posFilter) ? posFilter : null;

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return state.available.filter((p) => {
      if (!lineupFull && !eligible.has(p.position)) return false;
      if (activePos && p.position !== activePos) return false;
      if (q && !`${p.name} ${p.team}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [state.available, eligible, lineupFull, activePos, query]);

  // Pin queued players (in queue order) to the top of the list.
  const ordered = useMemo(() => {
    if (queue.length === 0) return visible;
    const byId = new Map(visible.map((p) => [p.id, p]));
    const top = queue.map((pid) => byId.get(pid)).filter(Boolean);
    const rest = visible.filter((p) => !queued.has(p.id));
    return [...top, ...rest];
  }, [visible, queue, queued]);

  function pick(player) {
    if (!isMyTurn || complete) return;
    impact(ImpactStyle.Medium);
    setError(null);
    conn
      ?.makePick(player.id)
      ?.receive('error', (r) => setError(`Can't draft: ${r.reason}`))
      ?.receive('timeout', () => setError('Pick didn’t go through — try again.'));
  }

  return (
    <View style={styles.board}>
      <View style={[styles.statusBar, isMyTurn && !complete && styles.statusBarMine]}>
        {!complete && state.current_picker_id ? (
          <Animated.View
            pointerEvents="none"
            style={[
              styles.pulseRing,
              {
                borderColor: colorFor(state.current_picker_id),
                opacity: pulse.interpolate({ inputRange: [0, 1], outputRange: [0.15, isMyTurn ? 0.95 : 0.5] }),
              },
            ]}
          />
        ) : null}
        {complete ? (
          <Text style={styles.turnDone}>🏁 Draft complete</Text>
        ) : (
          <>
            <Text style={[styles.turn, isMyTurn && styles.turnMine]}>
              {isMyTurn ? '🟢 Your pick' : `${nameFor(state.current_picker_id)} is picking…`}
            </Text>
            <View style={styles.statusRight}>
              <Text style={styles.pickNo}>
                Pick {state.pick_number}/{state.total_picks}
              </Text>
              <PickClock deadline={state.clock_deadline} serverNow={state.server_now} />
            </View>
          </>
        )}
      </View>

      <DraftOrderDots order={order} pickNumber={state.pick_number} colorFor={colorFor} />
      <DraftTicker picks={state.picks} nameFor={nameFor} />

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {flow ? (
        <>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.mySlotsStrip}
            contentContainerStyle={styles.mySlotsContent}
          >
            {state.slots.map((slot) => (
              <FlashSlotCard
                key={slot.key}
                slot={slot}
                pick={myPicks.find((p) => p.slot === slot.key)}
                tint={colorFor(myId)}
                styles={styles}
                colors={colors}
              />
            ))}
          </ScrollView>

          <View style={styles.seatTabs}>
            {players.map((p) => {
              const isMe = String(p.id) === String(myId);
              const onClock = !complete && String(state.current_picker_id) === String(p.id);
              return (
                <Pressable
                  key={p.id}
                  onPress={() => setSheetUid(p.id)}
                  style={({ pressed }) => [styles.seatTab, onClock && styles.seatTabCurrent, pressed && { opacity: 0.85 }]}
                >
                  <Avatar name={isMe ? 'You' : p.username} size={28} />
                  <View style={styles.seatTabNameRow}>
                    <View style={[styles.seatTabDot, { backgroundColor: colorFor(p.id) }]} />
                    <Text style={styles.seatTabName} numberOfLines={1}>
                      {isMe ? 'You' : p.username}
                    </Text>
                  </View>
                  <Text style={styles.seatTabCount}>
                    {picksFor(p.id).length}/{state.slots.length}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </>
      ) : (
        <View style={styles.rostersRow}>
          <View style={styles.rosterCol}>
            <Pressable style={styles.rosterHead} onPress={() => setSheetUid(myId)} hitSlop={6}>
              <View style={[styles.seatTabDot, { backgroundColor: colorFor(myId) }]} />
              <Text style={styles.rosterLabel} numberOfLines={1}>
                Your lineup
              </Text>
              <Ionicons name="chevron-expand" size={14} color={colors.muted} />
            </Pressable>
            <LineupSlots slots={state.slots} picks={myPicks} compact tint={colorFor(myId)} />
          </View>
          <View style={styles.rosterCol}>
            <Pressable style={styles.rosterHead} onPress={() => setSheetUid(oppId)} hitSlop={6}>
              <View style={[styles.seatTabDot, { backgroundColor: colorFor(oppId) }]} />
              <Text style={styles.rosterLabel} numberOfLines={1}>
                {nameFor(oppId)}
              </Text>
              <Ionicons name="chevron-expand" size={14} color={colors.muted} />
            </Pressable>
            <LineupSlots slots={state.slots} picks={oppPicks} compact tint={colorFor(oppId)} />
          </View>
        </View>
      )}

      {!complete ? (
        <>
          {lineupFull ? (
            <Text style={styles.watchNote}>Your lineup is full — watching {flow ? 'the others' : nameFor(oppId)} finish.</Text>
          ) : null}

          <SearchInput value={query} onChangeText={setQuery} placeholder="Search players or teams…" style={{ marginTop: spacing.md }} />

          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.chipRow} contentContainerStyle={styles.chipRowContent}>
            <Chip label="All" active={activePos === null} onPress={() => setPosFilter(null)} />
            {positions.map((pos) => (
              <Chip key={pos} label={pos} active={activePos === pos} onPress={() => setPosFilter(activePos === pos ? null : pos)} />
            ))}
          </ScrollView>

          {queue.length > 0 ? (
            <Text style={styles.queueHint}>★ {queue.length} queued — auto-pick drafts these first if your clock runs out.</Text>
          ) : null}

          <FlatList
            style={styles.list}
            data={ordered}
            keyExtractor={(p) => String(p.id)}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
            ListEmptyComponent={<EmptyState icon="search" title="No players match" subtitle="Adjust your search or position filter." />}
            renderItem={({ item }) => {
              const isQ = queued.has(item.id);
              return (
                <Pressable
                  onPress={() => pick(item)}
                  style={({ pressed }) => [
                    styles.player,
                    isQ && styles.playerQueued,
                    !isMyTurn && styles.playerDim,
                    pressed && isMyTurn && { opacity: 0.85, transform: [{ scale: 0.99 }] },
                  ]}
                >
                  <Avatar name={item.name} size={38} />
                  <View style={{ flex: 1, marginLeft: spacing.md }}>
                    <Text style={styles.playerName}>{item.name}</Text>
                    <Text style={styles.playerMeta}>
                      {item.position} · {item.team}
                      {nextGameLabel(item.next_game_at) ? (
                        <Text style={styles.gameTime}> · {nextGameLabel(item.next_game_at)}</Text>
                      ) : null}
                    </Text>
                  </View>
                  <Pressable onPress={() => toggleQueue(item.id)} hitSlop={8} style={{ paddingHorizontal: 4 }}>
                    <Ionicons name={isQ ? 'star' : 'star-outline'} size={22} color={isQ ? colors.accent : colors.muted} />
                  </Pressable>
                  <Pressable
                    onPress={() => navigation.navigate('PlayerProfile', { id: item.id, name: item.name, team: item.team, position: item.position })}
                    hitSlop={8}
                    style={{ paddingHorizontal: 4 }}
                  >
                    <Ionicons name="information-circle-outline" size={22} color={colors.muted} />
                  </Pressable>
                  <View style={[styles.projWrap, { marginLeft: spacing.sm }]}>
                    <Text style={styles.proj}>{(item.projection ?? 0).toFixed(1)}</Text>
                    <Text style={styles.projLabel}>FPG</Text>
                  </View>
                  {isMyTurn ? <Ionicons name="add-circle" size={24} color={colors.accent} style={{ marginLeft: spacing.sm }} /> : null}
                </Pressable>
              );
            }}
          />
        </>
      ) : (
        <View>
          <Text style={styles.completeNote}>
            Lineups are locked. The winner is declared once the games in the scoring window finish.
          </Text>
          <Button
            title="Watch Live Matchup"
            icon="pulse"
            onPress={() => navigation.navigate('LiveMatchup', { id: duelId, opponentName })}
            style={{ marginTop: spacing.xl }}
          />
          <Button
            title="Back to Duels"
            icon="list"
            variant="outline"
            onPress={() => navigation.popToTop()}
            style={{ marginTop: spacing.sm }}
          />
        </View>
      )}

      <RosterSheet
        visible={sheetUid != null}
        onClose={() => setSheetUid(null)}
        title={String(sheetUid) === String(myId) ? 'Your lineup' : `${nameFor(sheetUid)}'s lineup`}
        name={nameFor(sheetUid ?? myId)}
        slots={state.slots}
        picks={sheetUid != null ? picksFor(sheetUid) : []}
      />
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    dim: { color: colors.muted, marginTop: 12, textAlign: 'center' },

    lobby: { flex: 1, backgroundColor: colors.bg, padding: spacing.xl, justifyContent: 'center' },
    lobbyTitle: { color: colors.text, fontSize: font.titleLg, fontWeight: '800', textAlign: 'center' },
    readyRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md, marginTop: spacing.xl, marginBottom: spacing.xl },
    pill: { flexGrow: 1, flexBasis: '45%', borderRadius: radius.lg, borderWidth: 1, paddingVertical: spacing.lg, alignItems: 'center' },
    pillOn: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    pillOff: { borderColor: colors.border, backgroundColor: colors.card },
    pillName: { color: colors.text, fontWeight: '800', fontSize: font.bodyLg, marginTop: spacing.sm, maxWidth: '90%' },
    pillStateRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 6 },
    pillState: { color: colors.muted, fontSize: font.small, fontWeight: '600' },

    board: { flex: 1, backgroundColor: colors.bg, padding: spacing.md },
    statusBar: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      borderRadius: radius.md,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    statusBarMine: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    pulseRing: { ...StyleSheet.absoluteFillObject, borderRadius: radius.md, borderWidth: 2 },
    statusRight: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    turn: { color: colors.muted, fontSize: font.bodyLg, fontWeight: '700' },
    turnMine: { color: colors.accent },
    turnDone: { color: colors.text, fontSize: font.subtitle, fontWeight: '800' },
    pickNo: { color: colors.muted, fontSize: font.small },
    rostersRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.md },
    rosterCol: { flex: 1 },
    rosterHead: { flexDirection: 'row', alignItems: 'center', gap: 5, marginBottom: spacing.sm },
    rosterLabel: { color: colors.text, fontWeight: '700', flex: 1 },
    mySlotsStrip: { marginTop: spacing.md, flexGrow: 0 },
    mySlotsContent: { gap: spacing.sm, paddingRight: spacing.sm },
    slotCard: {
      width: 92,
      backgroundColor: colors.card,
      borderColor: colors.borderSubtle,
      borderWidth: 1,
      borderRadius: radius.md,
      paddingVertical: 6,
      paddingHorizontal: spacing.sm,
      alignItems: 'center',
    },
    slotCardFilled: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    slotCardLabel: { color: colors.muted, fontSize: 10, fontWeight: '800', letterSpacing: 0.5 },
    slotCardName: { color: colors.text, fontSize: font.caption, fontWeight: '600', marginTop: 2, maxWidth: 84 },
    seatTabs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm },
    seatTab: {
      flex: 1,
      alignItems: 'center',
      backgroundColor: colors.card,
      borderColor: colors.borderSubtle,
      borderWidth: 1,
      borderRadius: radius.md,
      paddingVertical: 6,
    },
    seatTabCurrent: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    seatTabNameRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2, maxWidth: '92%' },
    seatTabDot: { width: 7, height: 7, borderRadius: 4 },
    seatTabName: { color: colors.text, fontSize: 11, fontWeight: '700', flexShrink: 1 },
    seatTabCount: { color: colors.muted, fontSize: 10, fontWeight: '700', marginTop: 1 },
    chipRow: { marginTop: spacing.md, marginBottom: spacing.xs, flexGrow: 0 },
    chipRowContent: { gap: spacing.sm, paddingRight: spacing.sm },
    watchNote: { color: colors.muted, fontSize: font.small, marginTop: spacing.md, fontStyle: 'italic' },
    list: { flex: 1, marginTop: spacing.sm },
    player: { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.card, borderRadius: radius.md, borderWidth: 1, borderColor: colors.borderSubtle, padding: spacing.md, marginBottom: spacing.sm },
    playerQueued: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    playerDim: { opacity: 0.45 },
    queueHint: { color: colors.muted, fontSize: font.small, marginTop: spacing.sm, fontStyle: 'italic' },
    playerName: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    playerMeta: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    gameTime: { color: colors.accent, fontSize: font.small, fontWeight: '600' },
    projWrap: { alignItems: 'center' },
    proj: { color: colors.accent, fontSize: font.bodyLg, fontWeight: '800' },
    projLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
    completeNote: { color: colors.muted, textAlign: 'center', marginTop: spacing.xl, lineHeight: 20 },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
