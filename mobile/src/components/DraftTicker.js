import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useThemedStyles, spacing, radius, font } from '../theme';
import { shortName } from '../utils/names';

// Horizontal strip of recent picks, latest first: "P7 · You → A. Wilson".
// Auto-picks get a ⚡ so you can tell the clock made the call.
export default function DraftTicker({ picks, nameFor }) {
  const styles = useThemedStyles(makeStyles);
  if (!picks || picks.length === 0) return null;

  const recent = [...picks].reverse();

  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.strip} contentContainerStyle={styles.stripContent}>
      {recent.map((p, i) => (
        <View key={p.pick_number} style={[styles.pill, i === 0 && styles.pillLatest]}>
          <Text style={styles.pickNo}>P{p.pick_number}</Text>
          <Text style={styles.text} numberOfLines={1}>
            {nameFor(p.user_id)} → {p.auto_picked ? '⚡ ' : ''}
            <Text style={styles.playerName}>{shortName(p.player?.name)}</Text>
          </Text>
        </View>
      ))}
    </ScrollView>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    strip: { flexGrow: 0, marginTop: spacing.sm },
    stripContent: { gap: spacing.sm, paddingRight: spacing.sm, alignItems: 'center' },
    pill: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      borderRadius: radius.pill,
      paddingHorizontal: 10,
      paddingVertical: 5,
    },
    pillLatest: { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft },
    pickNo: { color: colors.placeholder, fontSize: 10, fontWeight: '800' },
    text: { color: colors.muted, fontSize: font.caption, fontWeight: '600', maxWidth: 220 },
    playerName: { color: colors.text },
  });
