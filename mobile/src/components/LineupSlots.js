import { StyleSheet, Text, View } from 'react-native';
import { useThemedStyles, spacing, radius, font } from '../theme';

// Renders a team's lineup: one row per slot (in template order), showing the
// drafted player or an empty placeholder.
export default function LineupSlots({ slots, picks }) {
  const styles = useThemedStyles(makeStyles);
  const bySlot = {};
  for (const p of picks || []) bySlot[p.slot] = p;

  return (
    <View style={styles.wrap}>
      {slots.map((slot, i) => {
        const pick = bySlot[slot.key];
        return (
          <View key={slot.key} style={[styles.row, i < slots.length - 1 && styles.divider]}>
            <View style={styles.slotChip}>
              <Text style={styles.slotText}>{slot.label}</Text>
            </View>
            {pick ? (
              <View style={{ flex: 1 }}>
                <Text style={styles.filled} numberOfLines={1}>
                  {pick.player.name}
                </Text>
                <Text style={styles.team} numberOfLines={1}>
                  {pick.player.team}
                  {pick.auto_picked ? ' · auto' : ''}
                </Text>
              </View>
            ) : (
              <Text style={styles.empty}>Empty</Text>
            )}
          </View>
        );
      })}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    wrap: { backgroundColor: colors.card, borderColor: colors.borderSubtle, borderWidth: 1, borderRadius: radius.md, paddingHorizontal: spacing.md },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    slotChip: { backgroundColor: colors.bgElevated, borderRadius: radius.sm, paddingHorizontal: 8, paddingVertical: 3, marginRight: spacing.md, minWidth: 42, alignItems: 'center' },
    slotText: { color: colors.muted, fontSize: 11, fontWeight: '800' },
    filled: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    team: { color: colors.muted, fontSize: font.caption, marginTop: 1 },
    empty: { color: colors.placeholder, fontSize: font.body, flex: 1 },
  });
