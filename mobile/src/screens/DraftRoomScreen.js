import { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useAuth } from '../auth/AuthContext';
import { connectDraft } from '../api/socket';
import PickClock from '../components/PickClock';
import LineupSlots from '../components/LineupSlots';
import { colors, spacing, radius, font } from '../theme';
import { Avatar, Button, Chip, SearchInput, EmptyState } from '../components/ui';

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
        <EmptyState
          icon="close-circle-outline"
          title="Draft cancelled"
          subtitle="No winner — nobody drafted. You can set up a new challenge."
        />
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

  // Buzz when it becomes my turn.
  const prevTurn = useRef(false);
  useEffect(() => {
    if (isMyTurn && !prevTurn.current && !complete) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    }
    prevTurn.current = isMyTurn;
  }, [isMyTurn, complete]);

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

  // Reconcile a stale position filter.
  const activePos = posFilter && positions.includes(posFilter) ? posFilter : null;

  // The board: hide players who can't fill any of my open slots, then apply the
  // position filter and the name/team search.
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
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});
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
            <Text style={[styles.turn, isMyTurn && styles.turnMine]}>
              {isMyTurn ? '🟢 Your pick' : `${opponentName} is picking…`}
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
            <Text style={styles.watchNote}>Your lineup is full — watching {opponentName} finish.</Text>
          ) : null}

          <SearchInput
            value={query}
            onChangeText={setQuery}
            placeholder="Search players or teams…"
            style={{ marginTop: spacing.md }}
          />

          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.chipRow} contentContainerStyle={styles.chipRowContent}>
            <Chip label="All" active={activePos === null} onPress={() => setPosFilter(null)} />
            {positions.map((pos) => (
              <Chip key={pos} label={pos} active={activePos === pos} onPress={() => setPosFilter(activePos === pos ? null : pos)} />
            ))}
          </ScrollView>

          <FlatList
            style={styles.list}
            data={visible}
            keyExtractor={(p) => String(p.id)}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
            ListEmptyComponent={<EmptyState icon="search" title="No players match" subtitle="Adjust your search or position filter." />}
            renderItem={({ item }) => (
              <Pressable
                onPress={() => pick(item)}
                disabled={!isMyTurn}
                style={({ pressed }) => [
                  styles.player,
                  !isMyTurn && styles.playerDim,
                  pressed && isMyTurn && { opacity: 0.85, transform: [{ scale: 0.99 }] },
                ]}
              >
                <Avatar name={item.name} size={38} />
                <View style={{ flex: 1, marginLeft: spacing.md }}>
                  <Text style={styles.playerName}>{item.name}</Text>
                  <Text style={styles.playerMeta}>
                    {item.position} · {item.team}
                  </Text>
                </View>
                <View style={styles.projWrap}>
                  <Text style={styles.proj}>{Math.round(item.projection)}</Text>
                  <Text style={styles.projLabel}>PROJ</Text>
                </View>
                {isMyTurn ? <Ionicons name="add-circle" size={24} color={colors.accent} style={{ marginLeft: spacing.sm }} /> : null}
              </Pressable>
            )}
          />
        </>
      ) : (
        <Text style={styles.completeNote}>
          Lineups are locked. The winner is declared once the games in the scoring window finish — check back from the duel screen.
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
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
  rosters: { marginTop: spacing.md, flexGrow: 0 },
  rosterCol: { width: 230, marginRight: spacing.md },
  rosterLabel: { color: colors.text, fontWeight: '700', marginBottom: spacing.sm },
  chipRow: { marginTop: spacing.md, marginBottom: spacing.xs, flexGrow: 0 },
  chipRowContent: { gap: spacing.sm, paddingRight: spacing.sm },
  watchNote: { color: colors.muted, fontSize: font.small, marginTop: spacing.md, fontStyle: 'italic' },
  list: { flex: 1, marginTop: spacing.sm },
  player: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  playerDim: { opacity: 0.45 },
  playerName: { color: colors.text, fontSize: font.body, fontWeight: '600' },
  playerMeta: { color: colors.muted, fontSize: font.small, marginTop: 2 },
  projWrap: { alignItems: 'center' },
  proj: { color: colors.accent, fontSize: font.bodyLg, fontWeight: '800' },
  projLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
  completeNote: { color: colors.muted, textAlign: 'center', marginTop: spacing.xl, lineHeight: 20 },
  error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
});
