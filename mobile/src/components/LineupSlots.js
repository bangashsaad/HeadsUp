import { useEffect, useRef } from 'react';
import { Animated, StyleSheet, Text, View } from 'react-native';
import { useThemedStyles, spacing, radius, font } from '../theme';
import { shortName } from '../utils/names';

// Renders a team's lineup: one row per slot (in template order), showing the
// drafted player or an empty placeholder. `compact` tightens rows to name-only
// ("A. Wilson", ⚡ when auto-picked) so two columns fit side by side on screen.
// When a pick lands, its row flashes in `tint` (the drafter's seat color).
export default function LineupSlots({ slots, picks, compact = false, tint }) {
  const styles = useThemedStyles(makeStyles);
  const bySlot = {};
  for (const p of picks || []) bySlot[p.slot] = p;

  return (
    <View style={styles.wrap}>
      {slots.map((slot, i) => (
        <SlotRow
          key={slot.key}
          slot={slot}
          pick={bySlot[slot.key]}
          compact={compact}
          divider={i < slots.length - 1}
          tint={tint}
          styles={styles}
        />
      ))}
    </View>
  );
}

function SlotRow({ slot, pick, compact, divider, tint, styles }) {
  const flash = useRef(new Animated.Value(0)).current;
  const prevId = useRef(pick?.player?.id);

  // Flash only when a NEW player lands in this slot. prevId starts as the
  // mount-time pick, so rejoining a draft in progress doesn't light the board.
  useEffect(() => {
    const id = pick?.player?.id;
    if (id && prevId.current !== id) {
      flash.setValue(1);
      Animated.timing(flash, { toValue: 0, duration: 900, useNativeDriver: true }).start();
    }
    prevId.current = id;
  }, [pick?.player?.id, flash]);

  return (
    <View style={[styles.row, compact && styles.rowCompact, divider && styles.divider]}>
      <Animated.View
        pointerEvents="none"
        style={[
          StyleSheet.absoluteFillObject,
          {
            backgroundColor: tint || '#4ade80',
            borderRadius: radius.sm,
            opacity: flash.interpolate({ inputRange: [0, 1], outputRange: [0, 0.3] }),
          },
        ]}
      />
      <View style={[styles.slotChip, compact && styles.slotChipCompact]}>
        <Text style={styles.slotText}>{slot.label}</Text>
      </View>
      {pick ? (
        compact ? (
          <Text style={styles.filledCompact} numberOfLines={1}>
            {shortName(pick.player.name)}
            {pick.auto_picked ? ' ⚡' : ''}
          </Text>
        ) : (
          <View style={{ flex: 1 }}>
            <Text style={styles.filled} numberOfLines={1}>
              {pick.player.name}
            </Text>
            <Text style={styles.team} numberOfLines={1}>
              {pick.player.team}
              {pick.auto_picked ? ' · auto' : ''}
            </Text>
          </View>
        )
      ) : (
        <Text style={[styles.empty, compact && styles.emptyCompact]}>Open slot</Text>
      )}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    wrap: { backgroundColor: colors.card, borderColor: colors.borderSubtle, borderWidth: 1, borderRadius: radius.md, paddingHorizontal: spacing.md },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm },
    rowCompact: { paddingVertical: 6 },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    slotChip: { backgroundColor: colors.bgElevated, borderRadius: radius.sm, paddingHorizontal: 8, paddingVertical: 3, marginRight: spacing.md, minWidth: 42, alignItems: 'center' },
    slotChipCompact: { minWidth: 34, paddingHorizontal: 6, marginRight: spacing.sm },
    slotText: { color: colors.muted, fontSize: 11, fontWeight: '800' },
    filled: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    filledCompact: { color: colors.text, fontSize: font.small, fontWeight: '600', flex: 1 },
    team: { color: colors.muted, fontSize: font.caption, marginTop: 1 },
    empty: { color: colors.placeholder, fontSize: font.body, flex: 1 },
    emptyCompact: { fontSize: font.small },
  });
