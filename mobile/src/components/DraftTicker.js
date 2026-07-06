import { useEffect, useRef } from 'react';
import { Animated, ScrollView, StyleSheet, Text } from 'react-native';
import { useThemedStyles, spacing, radius, fonts } from '../theme';
import { shortName } from '../utils/names';

// Horizontal strip of recent picks, latest first: "P7 · You → A. Wilson".
// Auto-picks get a ⚡ so you can tell the clock made the call. New pills are
// keyed by pick number, so only a fresh pick runs the slide-in.
export default function DraftTicker({ picks, nameFor }) {
  const styles = useThemedStyles(makeStyles);
  if (!picks || picks.length === 0) return null;

  const recent = [...picks].reverse();

  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.strip} contentContainerStyle={styles.stripContent}>
      {recent.map((p, i) => (
        <SlideIn key={p.pick_number}>
          <Animated.View style={[styles.pill, i === 0 && styles.pillLatest]}>
            <Text style={styles.pickNo}>P{p.pick_number}</Text>
            <Text style={styles.text} numberOfLines={1}>
              {nameFor(p.user_id)} → {p.auto_picked ? '⚡ ' : ''}
              <Text style={styles.playerName}>{shortName(p.player?.name)}</Text>
            </Text>
          </Animated.View>
        </SlideIn>
      ))}
    </ScrollView>
  );
}

function SlideIn({ children }) {
  const a = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.spring(a, { toValue: 1, friction: 7, tension: 90, useNativeDriver: true }).start();
  }, [a]);

  return (
    <Animated.View
      style={{
        opacity: a,
        transform: [{ translateX: a.interpolate({ inputRange: [0, 1], outputRange: [-24, 0] }) }],
      }}
    >
      {children}
    </Animated.View>
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
    pickNo: { color: colors.placeholder, fontSize: 9, fontFamily: fonts.bodyBlack },
    text: { color: colors.muted, fontSize: 12.5, fontFamily: fonts.condBold, maxWidth: 220 },
    playerName: { color: colors.text },
  });
