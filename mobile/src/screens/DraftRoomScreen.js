import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { connectDraft } from '../api/socket';
import PickClock from '../components/PickClock';
import LineupSlots from '../components/LineupSlots';
import { colors } from '../theme';

export default function DraftRoomScreen({ route }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token, user } = useAuth();
  const myId = user.id;

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
        <Text style={styles.cancelledTitle}>Draft cancelled</Text>
        <Text style={styles.dim}>No winner — nobody drafted. You can set up a new challenge.</Text>
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
      opponentName={opponentName}
      conn={connRef.current}
      error={error}
      setError={setError}
    />
  );
}

function Lobby({ state, myId, opponentName, conn }) {
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

      <TouchableOpacity
        style={[styles.readyBtn, iAmReady && styles.readyBtnDone]}
        onPress={() => conn?.ready()}
        disabled={iAmReady}
      >
        <Text style={styles.readyBtnText}>{iAmReady ? "Ready — waiting…" : "I'm Ready"}</Text>
      </TouchableOpacity>

      <TouchableOpacity style={styles.cancelBtn} onPress={() => conn?.cancel()}>
        <Text style={styles.cancelText}>Cancel draft (no-show)</Text>
      </TouchableOpacity>
    </View>
  );
}

function ReadyPill({ name, ready }) {
  return (
    <View style={[styles.pill, ready ? styles.pillOn : styles.pillOff]}>
      <Text style={styles.pillName}>{name}</Text>
      <Text style={styles.pillState}>{ready ? '✅ Ready' : '… not ready'}</Text>
    </View>
  );
}

function FilterChip({ label, active, onPress }) {
  return (
    <TouchableOpacity style={[styles.chip, active && styles.chipActive]} onPress={onPress}>
      <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
    </TouchableOpacity>
  );
}

function DraftBoard({ state, myId, opponentName, conn, error, setError }) {
  const complete = state.phase === 'complete';
  const isMyTurn = String(state.current_picker_id) === String(myId);

  const myPicks = useMemo(
    () => state.picks.filter((p) => String(p.user_id) === String(myId)),
    [state.picks, myId]
  );
  const oppPicks = useMemo(
    () => state.picks.filter((p) => String(p.user_id) !== String(myId)),
    [state.picks, myId]
  );

  // Which positions still fit one of my open slots.
  const eligible = useMemo(() => {
    const filled = new Set(myPicks.map((p) => p.slot));
    const open = state.slots.filter((s) => !filled.has(s.key));
    return new Set(open.flatMap((s) => s.eligible));
  }, [state.slots, myPicks]);

  const [query, setQuery] = useState('');
  const [posFilter, setPosFilter] = useState(null);

  // Once my lineup is full but the draft isn't over (the snake tail, where the
  // opponent still has a pick), every position is "ineligible" for me — so stop
  // filtering by eligibility and let me watch the full board instead of blanking.
  const lineupFull = !complete && eligible.size === 0;

  // Position chips: positions still on the board that I can draft (or, once my
  // lineup is full, any position) — so the chip row never offers a dead filter.
  const positions = useMemo(() => {
    const set = new Set(
      state.available.filter((p) => lineupFull || eligible.has(p.position)).map((p) => p.position)
    );
    return Array.from(set).sort();
  }, [state.available, eligible, lineupFull]);

  // Reconcile a stale position filter: if the chosen position is no longer on
  // the chip row (all drafted, or my slots for it filled), treat it as cleared
  // so the user never lands on an empty board with no active chip to undo.
  const activePos = posFilter && positions.includes(posFilter) ? posFilter : null;

  // The board: hide players who can't fill any of my open slots (declutter),
  // then apply the position filter and the name/team search.
  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return state.available.filter((p) => {
      if (!lineupFull && !eligible.has(p.position)) return false;
      if (activePos && p.position !== activePos) return false;
      if (q && !`${p.name} ${p.team}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [state.available, eligible, lineupFull, activePos, query]);

  function pick(player) {
    if (!isMyTurn || complete) return;
    setError(null);
    conn
      ?.makePick(player.id)
      ?.receive('error', (r) => setError(`Can't draft: ${r.reason}`))
      ?.receive('timeout', () => setError('Pick didn’t go through — try again.'));
  }

  return (
    <View style={styles.board}>
      <View style={styles.statusBar}>
        {complete ? (
          <Text style={styles.turnDone}>🏁 Draft complete</Text>
        ) : (
          <>
            <Text style={[styles.turn, isMyTurn && styles.turnMine]}>
              {isMyTurn ? 'Your pick' : `${opponentName} is picking`}
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

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <ScrollView style={styles.rosters} horizontal showsHorizontalScrollIndicator={false}>
        <View style={styles.rosterCol}>
          <Text style={styles.rosterLabel}>Your lineup</Text>
          <LineupSlots slots={state.slots} picks={myPicks} />
        </View>
        <View style={styles.rosterCol}>
          <Text style={styles.rosterLabel}>{opponentName}</Text>
          <LineupSlots slots={state.slots} picks={oppPicks} />
        </View>
      </ScrollView>

      {!complete ? (
        <>
          {lineupFull ? (
            <Text style={styles.watchNote}>
              Your lineup is full — watching {opponentName} finish.
            </Text>
          ) : null}

          <TextInput
            style={styles.search}
            placeholder="Search players or teams…"
            placeholderTextColor={colors.placeholder}
            value={query}
            onChangeText={setQuery}
            autoCorrect={false}
            autoCapitalize="none"
            clearButtonMode="while-editing"
          />

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.chipRow}
            contentContainerStyle={styles.chipRowContent}
          >
            <FilterChip label="All" active={activePos === null} onPress={() => setPosFilter(null)} />
            {positions.map((pos) => (
              <FilterChip
                key={pos}
                label={pos}
                active={activePos === pos}
                onPress={() => setPosFilter(activePos === pos ? null : pos)}
              />
            ))}
          </ScrollView>

          <FlatList
            style={styles.list}
            data={visible}
            keyExtractor={(p) => String(p.id)}
            keyboardShouldPersistTaps="handled"
            ListEmptyComponent={
              <Text style={styles.emptyList}>No available players match your filters.</Text>
            }
            renderItem={({ item }) => (
              <TouchableOpacity
                style={[styles.player, !isMyTurn && styles.playerDim]}
                onPress={() => pick(item)}
                disabled={!isMyTurn}
              >
                <View style={{ flex: 1 }}>
                  <Text style={styles.playerName}>{item.name}</Text>
                  <Text style={styles.playerMeta}>
                    {item.position} · {item.team}
                  </Text>
                </View>
                <Text style={styles.proj}>{Math.round(item.projection)}</Text>
              </TouchableOpacity>
            )}
          />
        </>
      ) : (
        <Text style={styles.completeNote}>
          Both lineups are set. Scoring &amp; the winner come in the next phase.
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
  dim: { color: colors.muted, marginTop: 12, textAlign: 'center' },

  lobby: { flex: 1, backgroundColor: colors.bg, padding: 24, justifyContent: 'center' },
  lobbyTitle: { color: colors.text, fontSize: 26, fontWeight: '800', textAlign: 'center' },
  readyRow: { flexDirection: 'row', gap: 12, marginTop: 28, marginBottom: 28 },
  pill: { flex: 1, borderRadius: 14, borderWidth: 1, padding: 16, alignItems: 'center' },
  pillOn: { borderColor: colors.accent, backgroundColor: '#14532d' },
  pillOff: { borderColor: colors.border, backgroundColor: colors.card },
  pillName: { color: colors.text, fontWeight: '800', fontSize: 16 },
  pillState: { color: colors.muted, marginTop: 6 },
  readyBtn: {
    backgroundColor: colors.accent,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
  },
  readyBtnDone: { backgroundColor: colors.card, borderWidth: 1, borderColor: colors.border },
  readyBtnText: { color: colors.bg, fontSize: 16, fontWeight: '700' },
  cancelBtn: { paddingVertical: 14, alignItems: 'center', marginTop: 8 },
  cancelText: { color: colors.danger, fontSize: 14, fontWeight: '600' },
  cancelledTitle: { color: colors.text, fontSize: 24, fontWeight: '800' },

  board: { flex: 1, backgroundColor: colors.bg, padding: 14 },
  statusBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  statusRight: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  turn: { color: colors.muted, fontSize: 16, fontWeight: '700' },
  turnMine: { color: colors.accent },
  turnDone: { color: colors.text, fontSize: 18, fontWeight: '800' },
  pickNo: { color: colors.muted, fontSize: 13 },
  rosters: { marginTop: 14, flexGrow: 0 },
  rosterCol: { width: 230, marginRight: 12 },
  rosterLabel: { color: colors.text, fontWeight: '700', marginBottom: 8 },
  boardLabel: { color: colors.text, fontWeight: '700', marginTop: 18, marginBottom: 8 },
  search: {
    backgroundColor: colors.card,
    color: colors.text,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    marginTop: 16,
  },
  chipRow: { marginTop: 10, marginBottom: 4, flexGrow: 0 },
  chipRowContent: { gap: 8, paddingRight: 8 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 16,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  chipActive: { backgroundColor: colors.accent, borderColor: colors.accent },
  chipText: { color: colors.muted, fontWeight: '700', fontSize: 13 },
  chipTextActive: { color: colors.bg },
  emptyList: { color: colors.muted, textAlign: 'center', marginTop: 24 },
  watchNote: { color: colors.muted, fontSize: 13, marginTop: 14, fontStyle: 'italic' },
  list: { flex: 1, marginTop: 8 },
  player: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: colors.border,
    padding: 12,
    marginBottom: 8,
  },
  playerDim: { opacity: 0.45 },
  playerName: { color: colors.text, fontSize: 15, fontWeight: '600' },
  playerMeta: { color: colors.muted, fontSize: 13, marginTop: 2 },
  proj: { color: colors.accent, fontSize: 16, fontWeight: '800' },
  completeNote: { color: colors.muted, textAlign: 'center', marginTop: 24, lineHeight: 20 },
  error: { color: colors.danger, textAlign: 'center', marginTop: 10 },
});
