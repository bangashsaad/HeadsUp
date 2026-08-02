import { useCallback, useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listFriends, listFriendGroups } from '../api/social';
import { getSportsStatus, listSlates } from '../api/sports';
import { createChallenge } from '../api/duels';
import { selection, impact, ImpactStyle } from '../haptics';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList, Button } from '../components/ui';

// Host + 4 rivals. Mirrors Participant.max_seat on the server.
const MAX_RIVALS = 4;

const LEAGUES = [
  { key: 'wnba', label: 'WNBA' },
  { key: 'mlb', label: 'MLB' },
  { key: 'nba', label: 'NBA' },
  { key: 'nfl', label: 'NFL' },
];

const ROSTERS = [5, 7];
const CLOCKS = [15, 30, 60];
const STAKES = [
  { coins: 0, label: 'FRIENDLY' },
  { coins: 25, label: '25' },
  { coins: 100, label: '100' },
];

// Display copy for the Roster Shapes modal. Mirrors Drafts.Lineup — the server
// is the authority; this only explains the shape you're picking.
const SHAPES = {
  wnba: { 5: ['2 GUARD', '2 FORWARD', '1 FLEX'], 7: ['3 GUARD', '3 FORWARD', '1 FLEX'] },
  nba: { 5: ['2 GUARD', '2 FORWARD', '1 FLEX'], 7: ['3 GUARD', '3 FORWARD', '1 FLEX'] },
  mlb: {
    5: ['1 PITCHER', '2 INFIELD', '1 OUTFIELD', '1 FLEX'],
    7: ['2 PITCHER', '2 INFIELD', '2 OUTFIELD', '1 FLEX'],
  },
  nfl: { 5: ['LEGACY SHAPE'], 7: ['LEGACY SHAPE'] },
};

const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

// ET calendar day (UTC-4) — the convention the server's Slate module uses.
function etDayISO(ms) {
  const d = new Date(ms - 4 * 3600 * 1000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

function slateLabel(iso) {
  if (iso === etDayISO(Date.now())) return 'TONIGHT';
  if (iso === etDayISO(Date.now() + 86400000)) return 'TOMORROW';
  const d = new Date(`${iso}T12:00:00Z`);
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

const isPlayable = (status, key) => {
  const st = status?.find?.((s) => s.sport === key);
  return !st || st.playable;
};

export default function CreateChallengeScreen({ navigation, route }) {
  // Tapping a face on Home's friend strip lands here with them already picked.
  const preselect = route?.params?.preselect;
  const { token, user, refreshUser } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [friends, setFriends] = useState([]);
  const [groups, setGroups] = useState([]);
  const [sportsStatus, setSportsStatus] = useState(null);
  const [slates, setSlates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  // Step 1 — the duel
  const [league, setLeague] = useState('wnba');
  // Basketball and baseball pick an ET DAY; football picks a WEEK, since a
  // team there plays once and a single night is two teams, not a league.
  // `slateId` holds whichever identifies the pick — an ISO date or "1-2".
  const [slateKind, setSlateKind] = useState('day');
  const [slateId, setSlateId] = useState(null);
  const [roster, setRoster] = useState(5);
  const [stake, setStake] = useState(0);
  const [customStake, setCustomStake] = useState('');
  const [customOpen, setCustomOpen] = useState(false);
  const [clock, setClock] = useState(30);
  const [shapesOpen, setShapesOpen] = useState(false);

  // Step 2 — send it to
  const [tab, setTab] = useState('everyone');
  const [selected, setSelected] = useState([]);

  const balance = user?.coins ?? 0;

  useEffect(() => {
    (async () => {
      try {
        const [f, g] = await Promise.all([listFriends(token), listFriendGroups(token).catch(() => ({ groups: [] }))]);
        const list = f.friends || [];
        setFriends(list);
        setGroups(g.groups || []);
        // Only honour it if they're really a friend — a stale param shouldn't
        // put a phantom id into the selection.
        if (preselect && list.some((x) => x.id === preselect)) setSelected([preselect]);
      } catch (e) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    })();
    getSportsStatus(token)
      .then((r) => setSportsStatus(r.sports))
      .catch(() => {});
  }, [token]);

  // Re-pull friends/groups on focus so a group made on the Friends tab shows up.
  useFocusEffect(
    useCallback(() => {
      listFriendGroups(token)
        .then((g) => setGroups(g.groups || []))
        .catch(() => {});
    }, [token])
  );

  // Slates for the chosen league; default to the first day with untipped games.
  useEffect(() => {
    let live = true;
    setSlates([]);
    setSlateId(null);
    listSlates(token, league)
      .then((res) => {
        if (!live) return;
        const kind = res.kind || 'day';
        const list = res.slates || [];
        setSlateKind(kind);
        setSlates(list);
        const first = list.find((d) => (d.upcoming ?? d.games) > 0);
        if (first) setSlateId(kind === 'week' ? first.key : first.date);
      })
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [token, league]);

  // Snap off an off-season league once the gate answers.
  useEffect(() => {
    if (sportsStatus && !isPlayable(sportsStatus, league)) {
      const first = LEAGUES.find((l) => isPlayable(sportsStatus, l.key));
      if (first) setLeague(first.key);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sportsStatus]);

  const playableLeagues = LEAGUES.filter((l) => isPlayable(sportsStatus, l.key));
  const slateIdOf = (d) => (slateKind === 'week' ? d.key : d.date);
  const slate = slates.find((d) => slateIdOf(d) === slateId);
  const slatePlayers = slate?.players ?? null;
  // The label a human reads, and the first day the draft has to beat.
  const slateName = slateKind === 'week' ? slate?.label || 'that week' : slateLabel(slate?.date || '');
  const slateStart = slate?.date || null;

  // The server rejects a slate that can't field roster x drafters x 2 bodies.
  // Mirror that here so sizes (and extra rivals) grey out BEFORE you send.
  const fits = useCallback(
    (size, drafters) => slatePlayers == null || slatePlayers >= size * drafters * 2,
    [slatePlayers]
  );

  const drafters = selected.length + 1;
  const rosterOk = (size) => fits(size, Math.max(drafters, 2));
  const canAddAnother = fits(roster, Math.max(drafters + 1, 2));

  // If the picked roster stops fitting (slate changed, or a rival joined),
  // fall back to the largest size that still works.
  useEffect(() => {
    if (!rosterOk(roster)) {
      const ok = [...ROSTERS].reverse().find((s) => rosterOk(s));
      if (ok) setRoster(ok);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slateId, slatePlayers, selected.length]);

  const visibleFriends = useMemo(() => {
    const base = [...friends].sort((a, b) => a.username.localeCompare(b.username));
    if (tab === 'everyone') return base;
    const g = groups.find((x) => String(x.id) === String(tab));
    if (!g) return base;
    const ids = new Set(g.member_ids || []);
    return base.filter((f) => ids.has(f.id));
  }, [friends, groups, tab]);

  function toggle(id) {
    setError(null);
    setSelected((cur) => {
      if (cur.includes(id)) {
        selection();
        return cur.filter((x) => x !== id);
      }
      if (cur.length >= MAX_RIVALS) {
        setError(`${MAX_RIVALS} rivals max — ${MAX_RIVALS + 1} drafters per duel.`);
        return cur;
      }
      if (!canAddAnother) {
        setError(`This slate can't field a ${roster}-slot draft for ${cur.length + 2} players.`);
        return cur;
      }
      impact(ImpactStyle.Light);
      return [...cur, id];
    });
  }

  const effectiveStake = stake === -1 ? Math.max(0, parseInt(customStake, 10) || 0) : stake;
  const stakeLabel =
    stake === -1 ? `◎ ${effectiveStake.toLocaleString()}` : stake === 0 ? 'FRIENDLY' : `◎ ${stake}`;
  const stakeAffordable = effectiveStake <= balance;

  // Leaving the custom sheet without a usable amount reverts to Friendly, so
  // the footer can never advertise "◎ 0" as a custom stake.
  function closeCustom() {
    setCustomOpen(false);
    const n = parseInt(customStake, 10) || 0;
    if (n < 1 || n > balance) {
      setStake(0);
      setCustomStake('');
    }
  }

  // BUG GUARD: a thin slate can leave NO roster size viable for the current
  // table (pick 4 rivals on a big slate, then switch to a one-game night).
  // Without this the CTA stayed live and the server rejected the send.
  const anyRosterFits = ROSTERS.some((size) => rosterOk(size));

  async function send() {
    if (selected.length === 0) return;
    if (!stakeAffordable) {
      setError(`You only have ◎ ${balance.toLocaleString()}.`);
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const who = selected.length === 1 ? { opponent_id: selected[0] } : { opponent_ids: selected };
      const res = await createChallenge(token, {
        ...who,
        sport: league,
        lineup_template: `${league}_${roster}`,
        pick_clock_seconds: clock,
        stake_coins: effectiveStake,
        draft_starts_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
        ...(slateId ? (slateKind === 'week' ? { slate_week: slateId } : { slate_date: slateId }) : {}),
      });
      refreshUser();
      // Straight to the lobby: watch acceptances land, then start.
      navigation.replace('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return (
      <Screen>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  if (friends.length === 0) {
    return (
      <Screen>
        <EmptyState
          icon="people-outline"
          title="A duel needs a rival"
          subtitle="Add a friend from the Friends tab first — then come back and set the terms."
        />
      </Screen>
    );
  }

  const cta = !anyRosterFits
    ? 'SLATE TOO SMALL'
    : selected.length === 0
      ? 'PICK WHO GETS IT'
      : selected.length === 1
        ? 'SEND TO 1'
        : `SEND TO ${selected.length}`;

  return (
    <Screen padded={false} edges={['bottom']}>
      <ScrollView contentContainerStyle={{ padding: spacing.lg, paddingBottom: 132 }} showsVerticalScrollIndicator={false}>
        <StepLabel n="1" title="THE DUEL" styles={styles} />

        <View style={styles.card}>
          <Row label="LEAGUE" styles={styles}>
            {playableLeagues.map((l) => (
              <Opt key={l.key} label={l.label} active={league === l.key} onPress={() => setLeague(l.key)} styles={styles} />
            ))}
          </Row>

          {slates.some((d) => (d.upcoming ?? d.games) > 0) ? (
            <Row label="SLATE" styles={styles} scroll>
              {slates
                .filter((d) => (d.upcoming ?? d.games) > 0 || slateIdOf(d) === slateId)
                .slice(0, 5)
                .map((d) => (
                  <Opt
                    key={slateIdOf(d)}
                    label={`${slateKind === 'week' ? d.label : slateLabel(d.date)} · ${d.upcoming ?? d.games}`}
                    active={slateId === slateIdOf(d)}
                    onPress={() => setSlateId(slateIdOf(d))}
                    styles={styles}
                  />
                ))}
            </Row>
          ) : null}

          <Row
            label="ROSTER"
            styles={styles}
            info={() => {
              selection();
              setShapesOpen(true);
            }}
          >
            {ROSTERS.map((size) => {
              const ok = rosterOk(size);
              return (
                <Opt
                  key={size}
                  label={String(size)}
                  active={roster === size}
                  disabled={!ok}
                  onPress={() => ok && setRoster(size)}
                  styles={styles}
                />
              );
            })}
          </Row>

          <Row label="STAKE" styles={styles}>
            {STAKES.map((s) => (
              <Opt
                key={s.coins}
                label={s.label}
                active={stake === s.coins}
                disabled={s.coins > balance}
                onPress={() => s.coins <= balance && setStake(s.coins)}
                styles={styles}
              />
            ))}
            <Opt
              label={stake === -1 && effectiveStake > 0 ? `◎ ${effectiveStake}` : 'CUSTOM'}
              active={stake === -1}
              onPress={() => {
                setStake(-1);
                setCustomOpen(true);
              }}
              styles={styles}
            />
          </Row>

          <Row label="PICK CLOCK" styles={styles} last>
            {CLOCKS.map((c) => (
              <Opt key={c} label={`${c}s`} active={clock === c} onPress={() => setClock(c)} styles={styles} />
            ))}
          </Row>
        </View>

        {slatePlayers != null && !anyRosterFits ? (
          <Text style={[styles.note, { color: colors.danger }]}>
            {slateName} can't field a draft for {drafters} players. Pick a bigger slate, or drop a
            rival.
          </Text>
        ) : slatePlayers != null && !rosterOk(7) ? (
          <Text style={styles.note}>
            {slateName} has {slate?.upcoming ?? 0} game{(slate?.upcoming ?? 0) === 1 ? '' : 's'} — not
            enough players for every roster size. Pick a bigger slate for deeper drafts.
          </Text>
        ) : null}

        <View style={styles.stepRow}>
          <StepLabel n="2" title="SEND IT TO" styles={styles} />
          <Text style={styles.counter}>
            {selected.length} / {MAX_RIVALS} SELECTED
          </Text>
        </View>

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, flexShrink: 0 }}>
          <View style={styles.tabRow}>
            <Tab label={`EVERYONE ${friends.length}`} active={tab === 'everyone'} onPress={() => setTab('everyone')} styles={styles} />
            {groups.map((g) => (
              <Tab
                key={g.id}
                label={`${g.name.toUpperCase()} ${(g.member_ids || []).length}`}
                active={String(tab) === String(g.id)}
                onPress={() => setTab(g.id)}
                styles={styles}
              />
            ))}
          </View>
        </ScrollView>

        {visibleFriends.length === 0 ? (
          <Text style={styles.note}>Nobody in this group yet — add friends to it from the Friends tab.</Text>
        ) : (
          <View style={styles.card}>
            {visibleFriends.map((f, i) => {
              const on = selected.includes(f.id);
              const blocked = !on && (selected.length >= MAX_RIVALS || !canAddAnother);
              return (
                <Pressable
                  key={f.id}
                  onPress={() => !blocked && toggle(f.id)}
                  style={({ pressed }) => [
                    styles.person,
                    i < visibleFriends.length - 1 && styles.divider,
                    blocked && { opacity: 0.4 },
                    pressed && !blocked && { backgroundColor: colors.cardElevated },
                  ]}
                >
                  <View>
                    <Avatar name={f.username} size={38} />
                    {f.online ? <View style={styles.onlineDot} /> : null}
                  </View>
                  <Text style={styles.personName} numberOfLines={1}>
                    {f.username}
                  </Text>
                  <Ionicons
                    name={on ? 'checkmark-circle' : 'ellipse-outline'}
                    size={23}
                    color={on ? colors.accent : colors.placeholder}
                  />
                </Pressable>
              );
            })}
          </View>
        )}

        <Text style={styles.footnote}>
          {MAX_RIVALS} rivals max — {MAX_RIVALS + 1} drafters per duel. Everyone who accepts is in; you start when ready.
        </Text>

        {error ? <Text style={styles.error}>{error}</Text> : null}
      </ScrollView>

      <View style={styles.footer}>
        <View style={styles.summaryRow}>
          <Text style={styles.summary} numberOfLines={1}>
            {league.toUpperCase()} · {roster} slots · {clock}s clock
          </Text>
          <Text style={[styles.stakeOut, !stakeAffordable && { color: colors.danger }]}>{stakeLabel}</Text>
        </View>
        <Button
          title={cta}
          icon={selected.length ? 'send' : undefined}
          variant={selected.length ? 'primary' : 'outline'}
          onPress={send}
          loading={submitting}
          disabled={selected.length === 0 || !anyRosterFits}
        />
      </View>

      <RosterShapesModal
        visible={shapesOpen}
        onClose={() => setShapesOpen(false)}
        league={league}
        roster={roster}
        onPick={(size) => rosterOk(size) && setRoster(size)}
        rosterOk={rosterOk}
        styles={styles}
        colors={colors}
      />

      <CustomStakeModal
        visible={customOpen}
        onClose={closeCustom}
        value={customStake}
        onChange={setCustomStake}
        balance={balance}
        styles={styles}
        colors={colors}
      />
    </Screen>
  );
}

function StepLabel({ n, title, styles }) {
  return (
    <View style={styles.stepLabel}>
      <View style={styles.pip}>
        <Text style={styles.pipText}>{n}</Text>
      </View>
      <Text style={styles.stepTitle}>{title}</Text>
    </View>
  );
}

function Row({ label, children, styles, last, info, scroll }) {
  const inner = <View style={styles.opts}>{children}</View>;
  return (
    <View style={[styles.row, !last && styles.divider]}>
      <View style={styles.rowHead}>
        <Text style={styles.rowLabel}>{label}</Text>
        {info ? (
          <Pressable onPress={info} hitSlop={16} style={styles.infoBtn}>
            <Ionicons name="information" size={13} color="#0A0B10" />
          </Pressable>
        ) : null}
      </View>
      {scroll ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0, flexShrink: 0 }}>
          {inner}
        </ScrollView>
      ) : (
        inner
      )}
    </View>
  );
}

function Opt({ label, active, disabled, onPress, styles }) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [styles.opt, active && styles.optActive, disabled && { opacity: 0.35 }, pressed && { opacity: 0.75 }]}
    >
      <Text style={[styles.optText, active && styles.optTextActive]}>{label}</Text>
    </Pressable>
  );
}

function Tab({ label, active, onPress, styles }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.tab, active && styles.tabActive, pressed && { opacity: 0.8 }]}>
      <Text style={[styles.tabText, active && styles.tabTextActive]}>{label}</Text>
    </Pressable>
  );
}

function RosterShapesModal({ visible, onClose, league, roster, onPick, rosterOk, styles, colors }) {
  const shapes = SHAPES[league] || {};
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <Text style={styles.sheetTitle}>ROSTER SHAPES</Text>
          <Text style={styles.sheetSub}>
            Every roster ends in one FLEX — positions lock as you draft. Shapes shown for {league.toUpperCase()}.
          </Text>
          {ROSTERS.map((size) => {
            const active = size === roster;
            const ok = rosterOk(size);
            return (
              <Pressable
                key={size}
                onPress={() => {
                  onPick(size);
                  onClose();
                }}
                disabled={!ok}
                style={[styles.shapeCard, active && styles.shapeCardActive, !ok && { opacity: 0.35 }]}
              >
                <Text style={[styles.shapeSize, active && { color: colors.accent }]}>{size} SLOTS</Text>
                <Text style={styles.shapeLine}>{(shapes[size] || []).join('  ·  ')}</Text>
                {!ok ? <Text style={styles.shapeWarn}>Not enough players on this slate</Text> : null}
              </Pressable>
            );
          })}
          <Button title="Done" variant="outline" onPress={onClose} style={{ marginTop: spacing.md }} />
        </Pressable>
      </Pressable>
    </Modal>
  );
}

function CustomStakeModal({ visible, onClose, value, onChange, balance, styles, colors }) {
  const n = parseInt(value, 10) || 0;
  const ok = n >= 1 && n <= balance;
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <Text style={styles.sheetTitle}>CUSTOM STAKE</Text>
          <Text style={styles.sheetSub}>Everyone puts in the same amount. You have ◎ {balance.toLocaleString()}.</Text>
          <TextInput
            value={value}
            onChangeText={(t) => onChange(t.replace(/[^0-9]/g, ''))}
            keyboardType="number-pad"
            placeholder="0"
            placeholderTextColor={colors.placeholder}
            style={styles.stakeInput}
            autoFocus
          />
          {value.length > 0 && !ok ? (
            <Text style={styles.shapeWarn}>{n > balance ? "That's more than you have." : 'Enter at least 1 coin.'}</Text>
          ) : null}
          <Button title="Set Stake" onPress={onClose} disabled={!ok} style={{ marginTop: spacing.md }} />
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    stepLabel: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: spacing.sm },
    stepRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.xl },
    pip: { width: 18, height: 18, borderRadius: 9, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center' },
    pipText: { color: '#0A0B10', fontSize: 11, fontFamily: fonts.bodyBlack },
    stepTitle: { color: colors.text, fontSize: 12, fontFamily: fonts.bodyExtra, letterSpacing: 2 },
    counter: { color: colors.muted, fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 1.5 },

    card: { backgroundColor: colors.card, borderRadius: 16, borderWidth: 1, borderColor: colors.border, overflow: 'hidden' },
    divider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.borderSubtle },

    row: { paddingHorizontal: 12, paddingVertical: 10 },
    rowHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 7 },
    rowLabel: { color: colors.muted, fontSize: 9.5, fontFamily: fonts.bodyExtra, letterSpacing: 2 },
    infoBtn: { width: 20, height: 20, borderRadius: 10, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center' },
    opts: { flexDirection: 'row', flexWrap: 'wrap', gap: 7 },

    opt: {
      minHeight: 36,
      paddingHorizontal: 14,
      justifyContent: 'center',
      borderRadius: 999,
      borderWidth: 1,
      borderColor: colors.border,
    },
    optActive: { backgroundColor: colors.accent, borderColor: colors.accent },
    optText: { color: colors.text, fontSize: 13, fontFamily: fonts.heroUpright, letterSpacing: 1 },
    optTextActive: { color: colors.onAccent },

    tabRow: { flexDirection: 'row', gap: 7, paddingVertical: spacing.sm },
    tab: { paddingHorizontal: 13, paddingVertical: 7, borderRadius: 999, borderWidth: 1, borderColor: colors.border },
    tabActive: { backgroundColor: colors.accent, borderColor: colors.accent },
    tabText: { color: colors.muted, fontSize: 11, fontFamily: fonts.bodyExtra, letterSpacing: 1 },
    tabTextActive: { color: colors.onAccent },

    person: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 12, paddingVertical: 9, minHeight: 56 },
    personName: { flex: 1, color: colors.text, fontSize: 15, fontFamily: fonts.bodyBold },
    onlineDot: {
      position: 'absolute',
      right: -1,
      bottom: -1,
      width: 11,
      height: 11,
      borderRadius: 6,
      backgroundColor: '#39D98A',
      borderWidth: 2,
      borderColor: colors.card,
    },

    note: { color: colors.muted, fontSize: 12, lineHeight: 18, marginTop: spacing.sm, fontFamily: fonts.body },
    footnote: { color: colors.placeholder, fontSize: 11, lineHeight: 17, marginTop: spacing.md, fontFamily: fonts.body },
    error: { color: colors.danger, fontSize: 13, marginTop: spacing.md, textAlign: 'center', fontFamily: fonts.bodyBold },

    footer: {
      position: 'absolute',
      left: 0,
      right: 0,
      bottom: 0,
      paddingHorizontal: spacing.lg,
      paddingTop: spacing.sm,
      paddingBottom: spacing.sm,
      backgroundColor: colors.bg,
      borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: colors.border,
    },
    summaryRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 7 },
    summary: { color: colors.muted, fontSize: 11, fontFamily: fonts.bodyExtra, letterSpacing: 1, flex: 1 },
    stakeOut: { color: colors.gold, fontSize: 12, fontFamily: fonts.bodyBlack, letterSpacing: 0.5 },

    backdrop: { flex: 1, backgroundColor: withAlpha('#000000', 0.65), justifyContent: 'center', padding: spacing.lg },
    sheet: { backgroundColor: colors.card, borderRadius: 18, borderWidth: 1, borderColor: colors.border, padding: spacing.lg },
    sheetTitle: { color: colors.text, fontSize: 15, fontFamily: fonts.heroUpright, letterSpacing: 1.5 },
    sheetSub: { color: colors.muted, fontSize: 12, lineHeight: 18, marginTop: 6, marginBottom: spacing.md, fontFamily: fonts.body },
    shapeCard: {
      borderRadius: 13,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
      padding: 13,
      marginBottom: spacing.sm,
    },
    shapeCardActive: { borderColor: colors.accent },
    shapeSize: { color: colors.text, fontSize: 13, fontFamily: fonts.heroUpright, letterSpacing: 1 },
    shapeLine: { color: colors.muted, fontSize: 12, marginTop: 4, fontFamily: fonts.condBold, letterSpacing: 0.5 },
    shapeWarn: { color: colors.danger, fontSize: 11, marginTop: 6, fontFamily: fonts.bodyBold },
    stakeInput: {
      color: colors.text,
      fontSize: 30,
      fontFamily: fonts.hero,
      textAlign: 'center',
      paddingVertical: 12,
      borderRadius: 13,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
    },
  });
