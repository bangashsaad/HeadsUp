import { StyleSheet, View } from 'react-native';
import { useThemedStyles, spacing } from '../theme';

// The snake order at a glance: one dot per pick in draft order. Your dots and
// theirs are tinted per player, past picks dim out, the current pick gets a
// ring. Scales to any roster size (wraps) and to N players later.
export default function DraftOrderDots({ order, pickNumber, colorFor }) {
  const styles = useThemedStyles(makeStyles);
  if (!order || order.length === 0) return null;

  return (
    <View style={styles.row}>
      {order.map((uid, i) => {
        const n = i + 1;
        const current = n === pickNumber;
        const done = n < pickNumber;
        return (
          <View
            key={n}
            style={[styles.dot, { backgroundColor: colorFor(uid) }, done && styles.done, current && styles.current]}
          />
        );
      })}
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    row: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', alignItems: 'center', gap: 5, marginTop: spacing.sm },
    dot: { width: 9, height: 9, borderRadius: 5 },
    done: { opacity: 0.3 },
    current: { width: 13, height: 13, borderRadius: 7, borderWidth: 2, borderColor: colors.text },
  });
