import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { listSlates } from '../api/sports';
import { useThemedStyles, spacing, font, fonts } from '../theme';
import { Chip, Button } from './ui';

// WNBA, MLB and NFL are live (real ESPN rosters/stats); NBA still uses a
// placeholder pool until its season + feed are wired, so the live ones lead.
// Off-season sports are dimmed by isPlayable below, not removed.
const SPORTS = [
  { key: 'wnba', label: '🏀 WNBA' },
  { key: 'mlb', label: '⚾️ Baseball' },
  { key: 'nfl', label: '🏈 Football' },
  { key: 'nba', label: '🏀 Basketball' },
];

// Off-season sports can't be picked (no games in the window = nothing to
// score). Unknown status (endpoint unreachable) fails open — the server
// backstops creation anyway.
function isPlayable(sportsStatus, key) {
  const st = sportsStatus?.find?.((s) => s.sport === key);
  return !st || st.playable;
}

// Roster sizes and clocks match the canonical challenge screen (async cut).
// Baseball runs 6/9; everyone else 5/7 — mirrors Drafts.Lineup.sizes_for/1.
const ROSTERS_BY_LEAGUE = { mlb: [6, 9] };
const rosterSizesFor = (lg) => ROSTERS_BY_LEAGUE[lg] || [5, 7];

const CLOCKS = [
  { secs: 15, label: '15s' },
  { secs: 30, label: '30s' },
  { secs: 60, label: '60s' },
];

const TIME_OPTIONS = [
  { label: 'In 1 hour', ms: 60 * 60 * 1000 },
  { label: 'In 3 hours', ms: 3 * 60 * 60 * 1000 },
  { label: 'Tomorrow', ms: 24 * 60 * 60 * 1000 },
  { label: 'In 2 days', ms: 2 * 24 * 60 * 60 * 1000 },
];

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

import { etDayISO } from '../time';

// "Tonight" / "Tomorrow" / "Wed Jul 15" for a slate's ISO date.
function slateLabel(iso) {
  const today = etDayISO(Date.now());
  const tomorrow = etDayISO(Date.now() + 24 * 3600 * 1000);
  if (iso === today) return 'Tonight';
  if (iso === tomorrow) return 'Tomorrow';
  const d = new Date(`${iso}T12:00:00Z`);
  return `${WEEKDAYS[d.getUTCDay()]} ${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}


export default function ChallengeForm({ initial = {}, onSubmit, submitLabel, submitting, sportsStatus }) {
  const styles = useThemedStyles(makeStyles);
  const { token } = useAuth();
  const [sport, setSport] = useState(initial.sport || 'wnba');
  const [roster, setRoster] = useState(() => {
    const sizes = rosterSizesFor(initial.sport || 'wnba');
    const n = parseInt((initial.lineup_template || '').split('_')[1], 10);
    return sizes.includes(n) ? n : sizes[0];
  });
  // A countered async duel falls back to the shortest clock we still offer.
  const [clockSecs, setClockSecs] = useState(() =>
    CLOCKS.some((c) => c.secs === initial.pick_clock_seconds) ? initial.pick_clock_seconds : 30
  );
  const [timeMs, setTimeMs] = useState(TIME_OPTIONS[0].ms);
  // Slates come in two shapes. Basketball and baseball answer with ET DAYS;
  // football answers with WEEKS, because a team there plays once and a single
  // night would offer two teams instead of the league. `slateId` is whichever
  // identifies the pick — an ISO date, or a week key like "1-2".
  const [slates, setSlates] = useState([]);
  const [slateKind, setSlateKind] = useState('day');
  const [slateId, setSlateId] = useState(null);

  // Each sport has its own size menu — switching sports snaps to it.
  useEffect(() => {
    const sizes = rosterSizesFor(sport);
    if (!sizes.includes(roster)) setRoster(sizes[0]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sport]);

  // If the selected sport turns out to be off-season, snap to the first
  // playable one once status arrives.
  useEffect(() => {
    if (sportsStatus && !isPlayable(sportsStatus, sport)) {
      const first = SPORTS.find((s) => isPlayable(sportsStatus, s.key));
      if (first) setSport(first.key);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sportsStatus]);

  // A day is pickable if games there haven't all tipped yet (the server
  // rejects tipped-out days — you'd be drafting known stat lines).
  const pickable = (d) => (d.upcoming ?? d.games) > 0;

  // The sport's next week of slates; default = the countered duel's slate
  // when it's still live, else the first day with playable games. An empty
  // answer (feed down) hides the picker — the server defaults.
  useEffect(() => {
    let live = true;
    setSlates([]);
    setSlateId(null);
    listSlates(token, sport)
      .then((res) => {
        if (!live) return;
        const kind = res.kind || 'day';
        const list = res.slates || [];
        setSlateKind(kind);
        setSlates(list);
        const idOf = (s) => (kind === 'week' ? s.key : s.date);
        const fromInitial =
          initial.slate_date && sport === initial.sport
            ? list.find((s) => s.date === initial.slate_date && pickable(s))
            : null;
        const first = fromInitial || list.find(pickable);
        if (first) setSlateId(idOf(first));
      })
      .catch(() => {});
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, sport]);

  const idOf = (s) => (slateKind === 'week' ? s.key : s.date);
  const selectedSlate = slates.find((s) => idOf(s) === slateId) || null;
  // A week's first game is what the draft has to beat, not its last.
  const slateStart = selectedSlate?.date || null;

  const anyGated = SPORTS.some((s) => !isPlayable(sportsStatus, s.key));

  // The draft has to happen on or before the slate day — dim times past it,
  // and snap back to the first legal one if the pick went stale. If NO time
  // fits (late night: every option crosses into the next ET day), bump the
  // slate forward instead of dead-ending the form.
  const timeAllowed = (ms) => !slateStart || etDayISO(Date.now() + ms) <= slateStart;

  useEffect(() => {
    if (timeAllowed(timeMs)) return;
    const first = TIME_OPTIONS.find((t) => timeAllowed(t.ms));
    if (first) {
      setTimeMs(first.ms);
    } else {
      const next = slates.find((s) => pickable(s) && s.date > slateStart);
      if (next) setSlateId(idOf(next));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slateStart, slates]);

  function handleSubmit() {
    onSubmit({
      sport,
      lineup_template: `${sport}_${roster}`,
      pick_clock_seconds: clockSecs,
      draft_starts_at: new Date(Date.now() + timeMs).toISOString(),
      ...(slateId ? (slateKind === 'week' ? { slate_week: slateId } : { slate_date: slateId }) : {}),
    });
  }

  return (
    <View>
      <Text style={styles.label}>Sport</Text>
      <View style={styles.row}>
        {SPORTS.map((s) => {
          const ok = isPlayable(sportsStatus, s.key);
          return (
            <View key={s.key} style={!ok && { opacity: 0.4 }}>
              <Chip label={ok ? s.label : `${s.label} · off-season`} active={sport === s.key} onPress={() => ok && setSport(s.key)} />
            </View>
          );
        })}
      </View>
      {anyGated ? <Text style={styles.gateNote}>Off-season sports come back when real games are on the slate.</Text> : null}

      {slates.some(pickable) ? (
        <>
          <Text style={styles.label}>{slateKind === 'week' ? 'Week — whose games count' : 'Slate — whose games count'}</Text>
          <View style={styles.row}>
            {slates
              .filter((s) => pickable(s) || idOf(s) === slateId)
              .slice(0, 5)
              .map((s) => (
                <Chip
                  key={idOf(s)}
                  label={`${slateKind === 'week' ? s.label : slateLabel(s.date)} · ${s.upcoming ?? s.games}`}
                  active={slateId === idOf(s)}
                  onPress={() => setSlateId(idOf(s))}
                />
              ))}
          </View>
          <Text style={styles.gateNote}>
            {slateKind === 'week'
              ? `Football runs by the week — every team plays once. You'll draft from all of ${
                  selectedSlate?.label?.toLowerCase() || 'that week'
                }, and it settles after the last game.`
              : `You'll only draft players who play ${
                  slateStart ? slateLabel(slateStart).toLowerCase() : 'that day'
                } — scoring covers just that slate.`}
          </Text>
        </>
      ) : null}

      <Text style={styles.label}>Roster</Text>
      <View style={styles.row}>
        {rosterSizesFor(sport).map((n) => (
          <Chip key={n} label={`${n} slots`} active={roster === n} onPress={() => setRoster(n)} />
        ))}
      </View>

      <Text style={styles.label}>Pick clock</Text>
      <View style={styles.row}>
        {CLOCKS.map((c) => (
          <Chip key={c.secs} label={c.label} active={clockSecs === c.secs} onPress={() => setClockSecs(c.secs)} />
        ))}
      </View>

      <Text style={styles.label}>When's the draft?</Text>
      <View style={styles.row}>
        {TIME_OPTIONS.map((t) => {
          const ok = timeAllowed(t.ms);
          return (
            <View key={t.label} style={!ok && { opacity: 0.4 }}>
              <Chip label={t.label} active={timeMs === t.ms} onPress={() => ok && setTimeMs(t.ms)} />
            </View>
          );
        })}
      </View>

      <Text style={styles.note}>Standard {sport.toUpperCase()} scoring applies — the full chart is shown on the challenge.</Text>

      <Button title={submitLabel} icon="send" onPress={handleSubmit} loading={submitting} style={{ marginTop: spacing.xl }} />
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    label: {
      color: colors.placeholder,
      fontSize: 10,
      fontFamily: fonts.bodyExtra,
      letterSpacing: 2,
      textTransform: 'uppercase',
      marginTop: spacing.lg,
      marginBottom: spacing.sm,
    },
    row: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
    note: { color: colors.muted, fontSize: font.small, marginTop: spacing.lg, lineHeight: 19 },
    gateNote: { color: colors.placeholder, fontSize: font.caption, marginTop: spacing.sm },
  });
