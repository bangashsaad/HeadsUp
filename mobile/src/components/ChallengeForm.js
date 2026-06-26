import { useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { colors } from '../theme';

const SPORTS = [
  { key: 'nfl', label: '🏈 Football' },
  { key: 'nba', label: '🏀 Basketball' },
  { key: 'mlb', label: '⚾️ Baseball' },
];

const ROSTER_SIZES = [3, 4, 5, 6, 8, 10];

// Draft-time presets — turned into an actual future timestamp at submit time.
const TIME_OPTIONS = [
  { label: 'In 1 hour', ms: 60 * 60 * 1000 },
  { label: 'In 3 hours', ms: 3 * 60 * 60 * 1000 },
  { label: 'Tomorrow', ms: 24 * 60 * 60 * 1000 },
  { label: 'In 2 days', ms: 2 * 24 * 60 * 60 * 1000 },
];

function Chip({ label, active, onPress }) {
  return (
    <TouchableOpacity style={[styles.chip, active && styles.chipActive]} onPress={onPress}>
      <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
    </TouchableOpacity>
  );
}

export default function ChallengeForm({ initial = {}, onSubmit, submitLabel, submitting }) {
  const [sport, setSport] = useState(initial.sport || 'nfl');
  const [rosterSize, setRosterSize] = useState(initial.roster_size || 5);
  const [timeMs, setTimeMs] = useState(TIME_OPTIONS[0].ms);

  function handleSubmit() {
    onSubmit({
      sport,
      roster_size: rosterSize,
      // Always compute from "now" so the draft time is guaranteed in the future.
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

      <Text style={styles.label}>Players each (roster size)</Text>
      <View style={styles.row}>
        {ROSTER_SIZES.map((n) => (
          <Chip key={n} label={String(n)} active={rosterSize === n} onPress={() => setRosterSize(n)} />
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

      <TouchableOpacity style={styles.button} onPress={handleSubmit} disabled={submitting}>
        {submitting ? (
          <ActivityIndicator color={colors.bg} />
        ) : (
          <Text style={styles.buttonText}>{submitLabel}</Text>
        )}
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  label: { color: colors.text, fontSize: 15, fontWeight: '700', marginTop: 18, marginBottom: 10 },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 9,
    borderRadius: 20,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  chipActive: { backgroundColor: colors.accent, borderColor: colors.accent },
  chipText: { color: colors.muted, fontWeight: '600' },
  chipTextActive: { color: colors.bg },
  note: { color: colors.muted, fontSize: 13, marginTop: 18, lineHeight: 19 },
  button: {
    backgroundColor: colors.accent,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    marginTop: 24,
  },
  buttonText: { color: colors.bg, fontSize: 16, fontWeight: '700' },
});
