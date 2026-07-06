import { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Easing, FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { connectDraft } from '../api/socket';
import { getDuel } from '../api/duels';
import { impact, notify, ImpactStyle, NotifyType } from '../haptics';
import PickClock from '../components/PickClock';
import LineupSlots from '../components/LineupSlots';
import DraftTicker from '../components/DraftTicker';
import DraftOrderDots from '../components/DraftOrderDots';
import RosterSheet from '../components/RosterSheet';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { Avatar, Button, Chip, SearchInput, EmptyState, GhostText, Pulse, Kicker, CondTitle, DisplayTitle } from '../components/ui';
import { shortName } from '../utils/names';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

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

function fmtClock(secs) {
  if (!secs) return null;
  if (secs < 120) return `${secs}S CLOCK`;
  if (secs < 7200) return `${Math.round(secs / 60)}M CLOCK`;
  return `${Math.round(secs / 3600)}H CLOCK`;
}

export default function DraftRoomScreen({ route, navigation }) {
  const { id, opponentName = 'Opponent' } = route.params;
  const { token, user } = useAuth();
  const myId = user.id;
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [state, setState] = useState(null);
  const [duel, setDuel] = useState(null); // terms for the ready room chips
  const [error, setError] = useState(null);
  const connRef = useRef(null);

  // The coin moment: shown once, live, when the lobby tips into drafting.
  const [flipping, setFlipping] = useState(false);
  const prevPhase = useRef(null);

  useEffect(() => {
    const conn = connectDraft(id, token, {
      onJoin: (reply) => setState(reply.state),
      onUpdate: (payload) => setState(payload.state),
      onError: () => setError('Could not join the draft room.'),
    });
    connRef.current = conn;
    return () => conn.leave();
  }, [id, token]);

  useEffect(() => {
    getDuel(token, id)
      .then((res) => setDuel(res?.duel || null))
      .catch(() => {});
  }, [token, id]);

  useEffect(() => {
    const ph = state?.phase;
    if (!ph) return;
    const prev = prevPhase.current;
    prevPhase.current = ph;
    if (prev === 'lobby' && ph !== 'lobby' && ph !== 'cancelled') {
      setFlipping(true);
      const t = setTimeout(() => setFlipping(false), 1600);
      return () => clearTimeout(t);
    }
  }, [state?.phase]);

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

  const body =
    state.phase === 'lobby' ? (
      <ReadyRoom state={state} duel={duel} myId={myId} opponentName={opponentName} conn={connRef.current} />
    ) : (
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

  return (
    <View style={{ flex: 1, backgroundColor: colors.bg }}>
      {body}
      {flipping ? <FlipOverlay /> : null}
    </View>
  );
}

// Spinning coin between "everyone's ready" and "pick 1 is on the clock".
function FlipOverlay() {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const spin = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(spin, { toValue: 1, duration: 1300, easing: Easing.out(Easing.cubic), useNativeDriver: true }).start();
  }, [spin]);

  return (
    <View style={styles.flipWrap}>
      <Animated.View
        style={[
          styles.coin,
          { transform: [{ rotateY: spin.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '1440deg'] }) }] },
        ]}
      >
        <View style={styles.coinInner}>
          <Text style={{ fontFamily: fonts.display, fontSize: 26, color: colors.accent }}>H</Text>
        </View>
      </Animated.View>
      <CondTitle size={22} color={colors.muted} style={{ letterSpacing: 2, marginTop: 22 }}>
        FLIPPING…
      </CondTitle>
      <Text style={styles.dim}>First pick goes to the coin</Text>
    </View>
  );
}

// The pre-draft room: faces, terms, one big pulsing READY.
function ReadyRoom({ state, duel, myId, opponentName, conn }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const players =
    state.players && state.players.length > 0
      ? state.players
      : Object.keys(state.ready || {}).map((id) => ({ id, username: opponentName }));
  const iAmReady = state.ready[String(myId)] || state.ready[myId];
  const two = players.length <= 2;
  const opp = players.find((p) => String(p.id) !== String(myId));

  const chips = [
    duel ? `${SPORT_EMOJI[duel.sport] || '🎯'} ${String(duel.sport || '').toUpperCase()}` : null,
    (state.slots || []).map((s) => s.label).join('·'),
    duel ? fmtClock(duel.pick_clock_seconds) : null,
    duel?.group ? `${players.length}-WAY` : 'SNAKE',
  ].filter(Boolean);

  return (
    <View style={styles.lobby}>
      <Kicker tracking={3} style={{ textAlign: 'center' }}>
        Draft room
      </Kicker>

      {two ? (
        <View style={styles.faceOff}>
          <View style={styles.faceCol}>
            <Avatar name={user2name(players, myId, opponentName).me} size={64} />
            <CondTitle size={16} italic={false} style={{ letterSpacing: 1, marginTop: 8 }}>
              YOU
            </CondTitle>
            <ReadyTag on={!!iAmReady} colors={colors} />
          </View>
          <GhostText size={34} color={withAlpha('#565D73', 0.9)} strokeWidth={1.4} style={{ marginHorizontal: 6 }}>
            VS
          </GhostText>
          <View style={styles.faceCol}>
            <Avatar name={opp?.username || opponentName} size={64} />
            <CondTitle size={16} italic={false} color={colors.purpleText} style={{ letterSpacing: 1, marginTop: 8 }} numberOfLines={1}>
              {(opp?.username || opponentName).toUpperCase()}
            </CondTitle>
            <ReadyTag on={!!(opp && state.ready[opp.id])} colors={colors} />
          </View>
        </View>
      ) : (
        <View style={styles.readyRow}>
          {players.map((p) => {
            const isMe = String(p.id) === String(myId);
            return (
              <View key={p.id} style={[styles.pill, state.ready[p.id] ? styles.pillOn : styles.pillOff]}>
                <Avatar name={isMe ? 'You' : p.username} size={44} />
                <Text style={styles.pillName} numberOfLines={1}>
                  {isMe ? 'You' : p.username}
                </Text>
                <ReadyTag on={!!state.ready[p.id]} colors={colors} />
              </View>
            );
          })}
        </View>
      )}

      <View style={styles.termsRow}>
        {chips.map((c) => (
          <View key={c} style={styles.termChip}>
            <Text style={styles.termChipText}>{c}</Text>
          </View>
        ))}
      </View>

      <Pulse color={withAlpha(colors.accent, 0.3)} disabled={!!iAmReady} style={{ marginTop: 30, alignSelf: 'stretch' }}>
        <Button
          title={iAmReady ? 'Ready — waiting…' : "I'm ready"}
          size="lg"
          onPress={() => conn?.ready()}
          disabled={!!iAmReady}
        />
      </Pulse>
      <Text style={[styles.dim, { marginTop: 14 }]}>Coin flip decides who's on the clock first</Text>
      <Button title="Cancel draft (no-show)" variant="ghost" onPress={() => conn?.cancel()} style={{ marginTop: spacing.sm }} />
    </View>
  );
}

function user2name(players, myId, opponentName) {
  const me = players.find((p) => String(p.id) === String(myId));
  return { me: me?.username || 'You', opp: players.find((p) => String(p.id) !== String(myId))?.username || opponentName };
}

function ReadyTag({ on, colors }) {
  return (
    <Text
      style={{
        marginTop: 5,
        fontSize: 9,
        fontFamily: fonts.bodyBlack,
        letterSpacing: 1.2,
        color: on ? colors.accent : colors.placeholder,
      }}
    >
      {on ? '✓ READY' : 'WAITING'}
    </Text>
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
  // lime was unreadable). You are always the accent; everyone else gets a
  // distinct tint in seat order — the first rival is always the purple side.
  const seatTint = useMemo(() => {
    const tints = [colors.purple, '#22E5FF', '#FFB021', '#FF4D8D', '#5CA8FF', '#FF7A1A'];
    const map = {};
    let i = 0;
    const ids = players.length > 0 ? players.map((p) => p.id) : Object.keys(state.ready || {});
    for (const id of ids) {
      if (String(id) === String(myId)) map[String(id)] = colors.accent;
      else map[String(id)] = tints[i++ % tints.length];
    }
    return map;
  }, [players, state.ready, myId, colors.accent, colors.purple]);

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

  const rounds = state.slots.length;
  const perRound = Math.max(1, Math.round((state.total_picks || rounds) / rounds));
  const round = Math.min(rounds, Math.ceil((state.pick_number || 1) / perRound));

  // ---- LOCKED IN. ----
  if (complete) {
    return (
      <View style={[styles.board, { justifyContent: 'center' }]}>
        <View style={{ alignItems: 'center', paddingHorizontal: spacing.lg }}>
          <DisplayTitle size={38} color={colors.accent}>
            LOCKED IN.
          </DisplayTitle>
          <Text style={styles.completeNote}>
            {flow ? 'All slips are sealed.' : 'Both slips are sealed.'} Scoring runs on the real box scores — the winner is
            called automatically.
          </Text>
          <Pulse color={withAlpha(colors.accent, 0.3)} style={{ alignSelf: 'stretch', marginTop: spacing.xl }}>
            <Button title="Watch it live →" onPress={() => navigation.navigate('LiveMatchup', { id: duelId, opponentName })} />
          </Pulse>
          <Button title="Back to duels" variant="outline" onPress={() => navigation.popToTop()} style={{ marginTop: spacing.sm }} />
        </View>
      </View>
    );
  }

  return (
    <View style={styles.board}>
      {/* Turn banner: who's up, pick/round, the clock — with a ghost pick no. */}
      <View style={[styles.turnCard, isMyTurn ? styles.turnCardMine : styles.turnCardTheirs]}>
        <View style={styles.turnGhost} pointerEvents="none">
          <GhostText size={56} color={withAlpha(colors.text, 0.08)} strokeWidth={1}>
            {String(Math.min(state.pick_number || 1, state.total_picks || 99)).padStart(2, '0')}
          </GhostText>
        </View>
        <View style={{ flex: 1, paddingRight: spacing.sm }}>
          <CondTitle size={20} color={isMyTurn ? colors.accent : colors.purpleText} numberOfLines={1} style={{ paddingRight: 4 }}>
            {isMyTurn ? "YOU'RE ON THE CLOCK" : `${nameFor(state.current_picker_id).toUpperCase()} IS PICKING…`}
          </CondTitle>
          <Kicker size={9.5} tracking={1.5} color={colors.muted} style={{ marginTop: 3 }}>
            {`Pick ${state.pick_number} of ${state.total_picks} · round ${round} of ${rounds}`}
          </Kicker>
        </View>
        <PickClock deadline={state.clock_deadline} serverNow={state.server_now} />
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
          <View style={[styles.rosterCol, { borderColor: withAlpha(colors.accent, 0.4) }]}>
            <Pressable style={styles.rosterHead} onPress={() => setSheetUid(myId)} hitSlop={6}>
              <Text style={[styles.rosterLabel, { color: colors.accent }]} numberOfLines={1}>
                YOUR SLIP
              </Text>
              <Text style={styles.rosterCount}>
                {myPicks.length}/{state.slots.length}
              </Text>
            </Pressable>
            <LineupSlots slots={state.slots} picks={myPicks} compact tint={colorFor(myId)} />
          </View>
          <View style={[styles.rosterCol, { borderColor: withAlpha(colors.purple, 0.4) }]}>
            <Pressable style={styles.rosterHead} onPress={() => setSheetUid(oppId)} hitSlop={6}>
              <Text style={[styles.rosterLabel, { color: colors.purpleText }]} numberOfLines={1}>
                {nameFor(oppId).toUpperCase()}
              </Text>
              <Text style={styles.rosterCount}>
                {oppPicks.length}/{state.slots.length}
              </Text>
            </Pressable>
            <LineupSlots slots={state.slots} picks={oppPicks} compact tint={colorFor(oppId)} />
          </View>
        </View>
      )}

      {lineupFull ? (
        <Text style={styles.watchNote}>Your slip is full — watching {flow ? 'the others' : nameFor(oppId)} finish.</Text>
      ) : null}

      <SearchInput value={query} onChangeText={setQuery} placeholder="Find a player…" style={{ marginTop: spacing.md }} />

      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.chipRow} contentContainerStyle={styles.chipRowContent}>
        <Chip label="All" active={activePos === null} onPress={() => setPosFilter(null)} />
        {positions.map((pos) => (
          <Chip key={pos} label={pos} active={activePos === pos} onPress={() => setPosFilter(activePos === pos ? null : pos)} />
        ))}
      </ScrollView>

      <View style={styles.queueHintRow}>
        <Ionicons name="star" size={11} color={colors.accent} />
        <Text style={styles.queueHint}>
          {queue.length > 0
            ? `${queue.length} queued — auto-pick grabs these if the clock dies`
            : 'Star players to queue them for auto-pick'}
        </Text>
      </View>

      <FlatList
        style={styles.list}
        data={ordered}
        keyExtractor={(p) => String(p.id)}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={<EmptyState icon="search" title="Nobody matches" subtitle="Loosen the search or clear the position filter." />}
        renderItem={({ item }) => {
          const isQ = queued.has(item.id);
          return (
            <Pressable
              onPress={() => pick(item)}
              style={({ pressed }) => [
                styles.player,
                isQ && styles.playerQueued,
                !isMyTurn && styles.playerDim,
                pressed && isMyTurn && { transform: [{ scale: 0.98 }] },
              ]}
            >
              <Avatar name={item.name} size={36} />
              <View style={{ flex: 1, marginLeft: 10, minWidth: 0 }}>
                <Text style={styles.playerName} numberOfLines={1}>
                  {item.name}
                </Text>
                <Text style={styles.playerMeta} numberOfLines={1}>
                  {item.position} · {item.team}
                  {nextGameLabel(item.next_game_at) ? ` · ${nextGameLabel(item.next_game_at)}` : ''}
                </Text>
              </View>
              <Pressable
                onPress={() => navigation.navigate('PlayerProfile', { id: item.id, name: item.name, team: item.team, position: item.position })}
                hitSlop={8}
                style={{ paddingHorizontal: 2 }}
              >
                <Ionicons name="information-circle-outline" size={19} color={colors.placeholder} />
              </Pressable>
              <View style={styles.projWrap}>
                <Text style={styles.proj}>{(item.projection ?? 0).toFixed(1)}</Text>
                <Text style={styles.projLabel}>PROJ</Text>
              </View>
              <Pressable onPress={() => toggleQueue(item.id)} hitSlop={8} style={[styles.starBtn, isQ && styles.starBtnOn]}>
                <Ionicons name={isQ ? 'star' : 'star-outline'} size={16} color={isQ ? colors.accent : colors.placeholder} />
              </Pressable>
            </Pressable>
          );
        }}
      />

      <RosterSheet
        visible={sheetUid != null}
        onClose={() => setSheetUid(null)}
        title={String(sheetUid) === String(myId) ? 'Your slip' : `${nameFor(sheetUid)}'s slip`}
        name={nameFor(sheetUid ?? myId)}
        slots={state.slots}
        picks={sheetUid != null ? picksFor(sheetUid) : []}
      />
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

const makeStyles = (colors) =>
  StyleSheet.create({
    center: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    dim: { color: colors.muted, marginTop: 12, textAlign: 'center', fontFamily: fonts.body, fontSize: 12.5 },

    flipWrap: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    coin: {
      width: 92,
      height: 92,
      borderRadius: 46,
      borderWidth: 4,
      borderColor: colors.accent,
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: colors.purple,
    },
    coinInner: {
      width: 74,
      height: 74,
      borderRadius: 37,
      backgroundColor: colors.bg,
      alignItems: 'center',
      justifyContent: 'center',
    },

    lobby: { flex: 1, backgroundColor: colors.bg, padding: spacing.xl, justifyContent: 'center' },
    faceOff: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 12, marginTop: spacing.xl },
    faceCol: { alignItems: 'center', maxWidth: 130 },
    readyRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md, marginTop: spacing.xl },
    pill: { flexGrow: 1, flexBasis: '45%', borderRadius: radius.lg, borderWidth: 1, paddingVertical: spacing.lg, alignItems: 'center' },
    pillOn: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    pillOff: { borderColor: colors.border, backgroundColor: colors.card },
    pillName: { color: colors.text, fontFamily: fonts.condBold, fontSize: font.bodyLg, marginTop: spacing.sm, maxWidth: '90%' },
    termsRow: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 7, marginTop: spacing.xl },
    termChip: {
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      borderRadius: 999,
      paddingVertical: 5,
      paddingHorizontal: 12,
    },
    termChipText: { fontSize: 11, fontFamily: fonts.bodyExtra, color: colors.muted, letterSpacing: 0.5 },

    board: { flex: 1, backgroundColor: colors.bg, padding: spacing.md },
    turnCard: {
      flexDirection: 'row',
      alignItems: 'center',
      borderRadius: 15,
      borderWidth: 1,
      paddingHorizontal: 14,
      paddingVertical: 10,
      overflow: 'hidden',
    },
    turnCardMine: { borderColor: withAlpha(colors.accent, 0.55), backgroundColor: withAlpha(colors.accent, 0.08) },
    turnCardTheirs: { borderColor: withAlpha(colors.purple, 0.45), backgroundColor: colors.card },
    turnGhost: { position: 'absolute', right: 64, top: -14 },

    rostersRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm },
    rosterCol: { flex: 1, borderWidth: 1, borderRadius: radius.md, padding: 6, backgroundColor: colors.card },
    rosterHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 4, marginBottom: 6 },
    rosterLabel: { fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, flexShrink: 1 },
    rosterCount: { color: colors.muted, fontFamily: fonts.condBold, fontSize: 12 },

    mySlotsStrip: { marginTop: spacing.md, flexGrow: 0 },
    mySlotsContent: { gap: spacing.sm, paddingRight: spacing.sm },
    slotCard: {
      width: 92,
      backgroundColor: colors.card,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: radius.md,
      paddingVertical: 6,
      paddingHorizontal: spacing.sm,
      alignItems: 'center',
    },
    slotCardFilled: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    slotCardLabel: { color: colors.muted, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },
    slotCardName: { color: colors.text, fontSize: font.caption, fontFamily: fonts.condBold, marginTop: 2, maxWidth: 84 },
    seatTabs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm },
    seatTab: {
      flex: 1,
      alignItems: 'center',
      backgroundColor: colors.card,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: radius.md,
      paddingVertical: 6,
    },
    seatTabCurrent: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    seatTabNameRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2, maxWidth: '92%' },
    seatTabDot: { width: 7, height: 7, borderRadius: 4 },
    seatTabName: { color: colors.text, fontSize: 11, fontFamily: fonts.bodyBold, flexShrink: 1 },
    seatTabCount: { color: colors.muted, fontSize: 10, fontFamily: fonts.bodyBold, marginTop: 1 },

    chipRow: { marginTop: spacing.sm, marginBottom: 2, flexGrow: 0 },
    chipRowContent: { gap: spacing.sm, paddingRight: spacing.sm },
    watchNote: { color: colors.muted, fontSize: font.small, marginTop: spacing.md, fontStyle: 'italic', fontFamily: fonts.body },
    queueHintRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 7 },
    queueHint: { color: colors.placeholder, fontSize: 10, fontFamily: fonts.bodyBold },
    list: { flex: 1, marginTop: spacing.sm },
    player: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderRadius: radius.md,
      borderWidth: 1,
      borderColor: colors.border,
      paddingVertical: 9,
      paddingHorizontal: 11,
      marginBottom: 7,
    },
    playerQueued: { borderColor: colors.accentBorder, backgroundColor: withAlpha(colors.accent, 0.07) },
    playerDim: { opacity: 0.45 },
    playerName: { color: colors.text, fontSize: 13.5, fontFamily: fonts.bodyBold },
    playerMeta: { color: colors.muted, fontSize: 10.5, fontFamily: fonts.bodySemi, marginTop: 1 },
    projWrap: { alignItems: 'flex-end', marginLeft: 6, minWidth: 40 },
    proj: { color: colors.accent, fontSize: 19, fontFamily: fonts.hero, lineHeight: 20 },
    projLabel: { color: colors.placeholder, fontSize: 8, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    starBtn: {
      width: 32,
      height: 32,
      borderRadius: 9,
      borderWidth: 1,
      borderColor: colors.border,
      alignItems: 'center',
      justifyContent: 'center',
      marginLeft: 8,
    },
    starBtnOn: { borderColor: withAlpha(colors.accent, 0.5), backgroundColor: withAlpha(colors.accent, 0.14) },
    completeNote: { color: colors.muted, textAlign: 'center', marginTop: spacing.md, lineHeight: 20, fontFamily: fonts.body, fontSize: 12.5 },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
