import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { colors, spacing, font } from '../theme';
import { Chip, Button } from './ui';

const SPORTS = [
  { key: 'nfl', label: '🏈 Football' },
  { key: 'nba', label: '🏀 Basketball' },
  { key: 'wnba', label: '🏀 WNBA' },
  { key: 'mlb', label: '⚾️ Baseball' },
];

// Lineup presets (the backend resolves "<sport>_<preset>" to positional slots
// and derives roster size from it). Quick = small lineup, Standard = full.
const PRESETS = [
  { key: 'quick', label: 'Quick' },
  { key: 'standard', label: 'Standard' },
];

// Per-pick clock. Short = live draft; multi-hour = async (same engine).
const CLOCKS = [
  { secs: 30, label: '30s' },
  { secs: 60, label: '60s' },
  { secs: 90, label: '90s' },
  { secs: 14400, label: '4h' },
  { secs: 43200, label: '12h' },
  { secs: 86400, label: '24h' },
];

// Draft-time presets — turned into an actual future timestamp at submit time.
const TIME_OPTIONS = [
  { label: 'In 1 hour', ms: 60 * 60 * 1000 },
  { label: 'In 3 hours', ms: 3 * 60 * 60 * 1000 },
  { label: 'Tomorrow', ms: 24 * 60 * 60 * 1000 },
  { label: 'In 2 days', ms: 2 * 24 * 60 * 60 * 1000 },
];

export default function ChallengeForm({ initial = {}, onSubmit, submitLabel, submitting }) {
  const [sport, setSport] = useState(initial.sport || 'nfl');
  const [preset, setPreset] = useState((initial.lineup_template || '').split('_')[1] || 'standard');
  const [clockSecs, setClockSecs] = useState(initial.pick_clock_seconds || 60);
  const [timeMs, setTimeMs] = useState(TIME_OPTIONS[0].ms);

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
        {SPORTS.map((s) => (
          <Chip key={s.key} label={s.label} active={sport === s.key} onPress={() => setSport(s.key)} />
        ))}
      </View>

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

      <Text style={styles.note}>
        Standard {sport.toUpperCase()} scoring applies — the full chart is shown on the challenge.
      </Text>

      <Button title={submitLabel} icon="send" onPress={handleSubmit} loading={submitting} style={{ marginTop: spacing.xl }} />
    </View>
  );
}

const styles = StyleSheet.create({
  label: { color: colors.text, fontSize: font.body, fontWeight: '700', marginTop: spacing.lg, marginBottom: spacing.sm },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  note: { color: colors.muted, fontSize: font.small, marginTop: spacing.lg, lineHeight: 19 },
});
