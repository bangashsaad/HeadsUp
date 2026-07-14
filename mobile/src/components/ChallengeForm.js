import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { listSlates } from '../api/sports';
import { useThemedStyles, spacing, font, fonts } from '../theme';
import { Chip, Button } from './ui';

// WNBA + MLB are live (real ESPN rosters/stats); NBA/NFL use placeholder pools
// until their seasons + feeds are wired, so the in-season pair leads.
const SPORTS = [
  { key: 'wnba', label: '🏀 WNBA' },
  { key: 'mlb', label: '⚾️ Baseball' },
  { key: 'nba', label: '🏀 Basketball' },
  { key: 'nfl', label: '🏈 Football' },
];

// Off-season sports can't be picked (no games in the window = nothing to
// score). Unknown status (endpoint unreachable) fails open — the server
// backstops creation anyway.
function isPlayable(sportsStatus, key) {
  const st = sportsStatus?.find?.((s) => s.sport === key);
  return !st || st.playable;
}

const PRESETS = [
  { key: 'quick', label: 'Quick' },
  { key: 'standard', label: 'Standard' },
];

const CLOCKS = [
  { secs: 30, label: '30s' },
  { secs: 60, label: '60s' },
  { secs: 90, label: '90s' },
  { secs: 14400, label: '4h' },
  { secs: 43200, label: '12h' },
  { secs: 86400, label: '24h' },
];

const TIME_OPTIONS = [
  { label: 'In 1 hour', ms: 60 * 60 * 1000 },
  { label: 'In 3 hours', ms: 3 * 60 * 60 * 1000 },
  { label: 'Tomorrow', ms: 24 * 60 * 60 * 1000 },
  { label: 'In 2 days', ms: 2 * 24 * 60 * 60 * 1000 },
];

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// A UTC instant's ET calendar day as "YYYY-MM-DD" (UTC-4, the season-long
// convention shared with the server's Slate/WindowScan).
function etDayISO(ms) {
  const d = new Date(ms - 4 * 3600 * 1000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

// "Tonight" / "Tomorrow" / "Wed Jul 15" for a slate's ISO date.
function slateLabel(iso) {
  const today = etDayISO(Date.now());
  const tomorrow = etDayISO(Date.now() + 24 * 3600 * 1000);
  if (iso === today) return 'Tonight';
  if (iso === tomorrow) return 'Tomorrow';
  const d = new Date(`${iso}T12:00:00Z`);
  return `${WEEKDAYS[d.getUTCDay()]} ${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

// Coin stakes: every player antes the same amount into escrow; winner takes
// the pot. 0 = friendly (bragging rights only).
const STAKES = [
  { coins: 0, label: 'Friendly' },
  { coins: 25, label: '◎ 25' },
  { coins: 100, label: '◎ 100' },
  { coins: 500, label: '◎ 500' },
];

export default function ChallengeForm({ initial = {}, onSubmit, submitLabel, submitting, sportsStatus }) {
  const styles = useThemedStyles(makeStyles);
  const { user, token } = useAuth();
  const [sport, setSport] = useState(initial.sport || 'wnba');
  const [preset, setPreset] = useState((initial.lineup_template || '').split('_')[1] || 'standard');
  const [clockSecs, setClockSecs] = useState(initial.pick_clock_seconds || 60);
  const [timeMs, setTimeMs] = useState(TIME_OPTIONS[0].ms);
  const [stake, setStake] = useState(initial.stake_coins || 0);
  const [slates, setSlates] = useState([]); // [{date: 'YYYY-MM-DD', games: n}]
  const [slateDate, setSlateDate] = useState(null);

  const balance = user?.coins ?? 0;

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
    setSlateDate(null);
    listSlates(token, sport)
      .then((res) => {
        if (!live) return;
        const days = res.slates || [];
        setSlates(days);
        const fromInitial =
          initial.slate_date && sport === initial.sport
            ? days.find((d) => d.date === initial.slate_date && pickable(d))
            : null;
        const first = fromInitial || days.find(pickable);
        if (first) setSlateDate(first.date);
      })
      .catch(() => {});
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, sport]);

  const anyGated = SPORTS.some((s) => !isPlayable(sportsStatus, s.key));

  // The draft has to happen on or before the slate day — dim times past it,
  // and snap back to the first legal one if the pick went stale. If NO time
  // fits (late night: every option crosses into the next ET day), bump the
  // slate forward instead of dead-ending the form.
  const timeAllowed = (ms) => !slateDate || etDayISO(Date.now() + ms) <= slateDate;

  useEffect(() => {
    if (timeAllowed(timeMs)) return;
    const first = TIME_OPTIONS.find((t) => timeAllowed(t.ms));
    if (first) {
      setTimeMs(first.ms);
    } else {
      const next = slates.find((d) => pickable(d) && d.date > slateDate);
      if (next) setSlateDate(next.date);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slateDate, slates]);

  function handleSubmit() {
    onSubmit({
      sport,
      lineup_template: `${sport}_${preset}`,
      pick_clock_seconds: clockSecs,
      draft_starts_at: new Date(Date.now() + timeMs).toISOString(),
      stake_coins: stake,
      ...(slateDate ? { slate_date: slateDate } : {}),
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
          <Text style={styles.label}>Slate — whose games count</Text>
          <View style={styles.row}>
            {slates
              .filter((d) => pickable(d) || d.date === slateDate)
              .slice(0, 5)
              .map((d) => (
                <Chip
                  key={d.date}
                  label={`${slateLabel(d.date)} · ${d.upcoming ?? d.games}`}
                  active={slateDate === d.date}
                  onPress={() => setSlateDate(d.date)}
                />
              ))}
          </View>
          <Text style={styles.gateNote}>
            You'll only draft players who play {slateDate ? slateLabel(slateDate).toLowerCase() : 'that day'} — scoring
            covers just that slate.
          </Text>
        </>
      ) : null}

      <Text style={styles.label}>Lineup</Text>
      <View style={styles.row}>
        {PRESETS.map((p) => (
          <Chip key={p.key} label={p.label} active={preset === p.key} onPress={() => setPreset(p.key)} />
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

      <Text style={styles.label}>Stake</Text>
      <View style={styles.row}>
        {STAKES.map((s) => {
          const affordable = s.coins <= balance;
          return (
            <View key={s.coins} style={!affordable && { opacity: 0.4 }}>
              <Chip label={s.label} active={stake === s.coins} onPress={() => affordable && setStake(s.coins)} />
            </View>
          );
        })}
      </View>
      <Text style={styles.stakeNote}>
        {stake === 0
          ? `Bragging rights only. You have ◎ ${balance.toLocaleString()}.`
          : `Everyone puts in ◎ ${stake} — winner takes all. You have ◎ ${balance.toLocaleString()}.`}
      </Text>

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
    stakeNote: { color: colors.gold, fontSize: font.caption, marginTop: spacing.sm },
  });
