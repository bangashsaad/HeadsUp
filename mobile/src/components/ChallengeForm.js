import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
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

export default function ChallengeForm({ initial = {}, onSubmit, submitLabel, submitting, sportsStatus }) {
  const styles = useThemedStyles(makeStyles);
  const [sport, setSport] = useState(initial.sport || 'wnba');
  const [preset, setPreset] = useState((initial.lineup_template || '').split('_')[1] || 'standard');
  const [clockSecs, setClockSecs] = useState(initial.pick_clock_seconds || 60);
  const [timeMs, setTimeMs] = useState(TIME_OPTIONS[0].ms);

  // If the selected sport turns out to be off-season, snap to the first
  // playable one once status arrives.
  useEffect(() => {
    if (sportsStatus && !isPlayable(sportsStatus, sport)) {
      const first = SPORTS.find((s) => isPlayable(sportsStatus, s.key));
      if (first) setSport(first.key);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sportsStatus]);

  const anyGated = SPORTS.some((s) => !isPlayable(sportsStatus, s.key));

  function handleSubmit() {
    onSubmit({
      sport,
      lineup_template: `${sport}_${preset}`,
      pick_clock_seconds: clockSecs,
      draft_starts_at: new Date(Date.now() + timeMs).toISOString(),
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
        {TIME_OPTIONS.map((t) => (
          <Chip key={t.label} label={t.label} active={timeMs === t.ms} onPress={() => setTimeMs(t.ms)} />
        ))}
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
