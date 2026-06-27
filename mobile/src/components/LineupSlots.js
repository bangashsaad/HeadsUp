import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

// Renders a team's lineup: one row per slot (in template order), showing the
// drafted player or an empty placeholder. `slots` = [{key,label,eligible}],
// `picks` = that user's picks [{slot, player, auto_picked}].
export default function LineupSlots({ slots, picks }) {
  const bySlot = {};
  for (const p of picks || []) bySlot[p.slot] = p;

  return (
    <View style={styles.wrap}>
      {slots.map((slot) => {
        const pick = bySlot[slot.key];
        return (
          <View key={slot.key} style={styles.row}>
            <Text style={styles.slot}>{slot.label}</Text>
            {pick ? (
              <Text style={styles.filled} numberOfLines={1}>
                {pick.player.name} · {pick.player.team}
                {pick.auto_picked ? '  (auto)' : ''}
              </Text>
            ) : (
              <Text style={styles.empty}>—</Text>
            )}
          </View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 14,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  slot: { color: colors.muted, fontSize: 13, fontWeight: '700', width: 56 },
  filled: { color: colors.text, fontSize: 15, fontWeight: '600', flex: 1 },
  empty: { color: colors.placeholder, fontSize: 15, flex: 1 },
});
