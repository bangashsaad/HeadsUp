import { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { connectDraft } from '../api/socket';
import { impact, notify, ImpactStyle, NotifyType } from '../haptics';
import PickClock from '../components/PickClock';
import LineupSlots from '../components/LineupSlots';
import DraftTicker from '../components/DraftTicker';
import DraftOrderDots from '../components/DraftOrderDots';
import RosterSheet from '../components/RosterSheet';
import { useTheme, useThemedStyles, spacing, radius, font, avatarColor } from '../theme';
import { Avatar, Button, Chip, SearchInput, EmptyState } from '../components/ui';

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
  const iAmReady = state.ready[String(myId)];
  const oppId = Object.keys(state.ready).find((uid) => uid !== String(myId));
  const oppReady = state.ready[oppId];

  return (
    <View style={styles.lobby}>
      <Text style={styles.lobbyTitle}>Draft Lobby</Text>
      <Text style={styles.dim}>Both players must be ready to start.</Text>

      <View style={styles.readyRow}>
        <ReadyPill name="You" ready={iAmReady} />
        <ReadyPill name={opponentName} ready={oppReady} />
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

  const myPicks = useMemo(() => state.picks.filter((p) => String(p.user_id) === String(myId)), [state.picks, myId]);
  const oppPicks = useMemo(() => state.picks.filter((p) => String(p.user_id) !== String(myId)), [state.picks, myId]);

  // Full snake order, derived the same way the server builds it: odd rounds
  // run [first, other], even rounds reverse. Known once the coin flip lands.
  const order = useMemo(() => {
    const first = state.first_picker_id;
    if (!first) return [];
    const other = Object.keys(state.ready || {}).find((u) => String(u) !== String(first)) ?? first;
    const out = [];
    for (let r = 1; r <= state.slots.length; r++) {
      if (r % 2 === 1) out.push(first, other);
      else out.push(other, first);
    }
    return out;
  }, [state.first_picker_id, state.ready, state.slots.length]);

  const oppTint = avatarColor(opponentName);
  const nameFor = (uid) => (String(uid) === String(myId) ? 'You' : opponentName);
  const colorFor = (uid) => (String(uid) === String(myId) ? colors.accent : oppTint);
  const [sheetSide, setSheetSide] = useState(null); // 'me' | 'opp' | null

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
        {complete ? (
          <Text style={styles.turnDone}>🏁 Draft complete</Text>
        ) : (
          <>
            <Text style={[styles.turn, isMyTurn && styles.turnMine]}>{isMyTurn ? '🟢 Your pick' : `${opponentName} is picking…`}</Text>
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

      <View style={styles.rostersRow}>
        <View style={styles.rosterCol}>
          <Pressable style={styles.rosterHead} onPress={() => setSheetSide('me')} hitSlop={6}>
            <Text style={styles.rosterLabel} numberOfLines={1}>
              Your lineup
            </Text>
            <Ionicons name="chevron-expand" size={14} color={colors.muted} />
          </Pressable>
          <LineupSlots slots={state.slots} picks={myPicks} compact />
        </View>
        <View style={styles.rosterCol}>
          <Pressable style={styles.rosterHead} onPress={() => setSheetSide('opp')} hitSlop={6}>
            <Text style={styles.rosterLabel} numberOfLines={1}>
              {opponentName}
            </Text>
            <Ionicons name="chevron-expand" size={14} color={colors.muted} />
          </Pressable>
          <LineupSlots slots={state.slots} picks={oppPicks} compact />
        </View>
      </View>

      {!complete ? (
        <>
          {lineupFull ? <Text style={styles.watchNote}>Your lineup is full — watching {opponentName} finish.</Text> : null}

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
        visible={sheetSide !== null}
        onClose={() => setSheetSide(null)}
        title={sheetSide === 'me' ? 'Your lineup' : `${opponentName}'s lineup`}
        name={sheetSide === 'me' ? 'You' : opponentName}
        slots={state.slots}
        picks={sheetSide === 'me' ? myPicks : oppPicks}
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
    readyRow: { flexDirection: 'row', gap: spacing.md, marginTop: spacing.xl, marginBottom: spacing.xl },
    pill: { flex: 1, borderRadius: radius.lg, borderWidth: 1, paddingVertical: spacing.lg, alignItems: 'center' },
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
    statusRight: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    turn: { color: colors.muted, fontSize: font.bodyLg, fontWeight: '700' },
    turnMine: { color: colors.accent },
    turnDone: { color: colors.text, fontSize: font.subtitle, fontWeight: '800' },
    pickNo: { color: colors.muted, fontSize: font.small },
    rostersRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.md },
    rosterCol: { flex: 1 },
    rosterHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 4, marginBottom: spacing.sm },
    rosterLabel: { color: colors.text, fontWeight: '700', flexShrink: 1 },
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
