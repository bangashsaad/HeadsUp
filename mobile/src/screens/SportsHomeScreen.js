import { StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, useThemedStyles, spacing, font } from '../theme';
import { Screen, Card, Badge } from '../components/ui';

const SPORTS = [
  { sport: 'nfl', label: 'Football', emoji: '🏈', tint: '#fb923c' },
  { sport: 'nba', label: 'Basketball', emoji: '🏀', tint: '#f87171' },
  { sport: 'wnba', label: 'WNBA', emoji: '🏀', tint: '#ec4899', live: true },
  { sport: 'mlb', label: 'Baseball', emoji: '⚾️', tint: '#3b82f6' },
];

export default function SportsHomeScreen({ navigation }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  return (
    <Screen scroll>
      <Text style={styles.heading}>Browse player pools</Text>
      <Text style={styles.sub}>Scout the talent before you challenge a friend.</Text>

      {SPORTS.map((s) => (
        <Card key={s.sport} onPress={() => navigation.navigate('Players', { sport: s.sport, label: s.label })} style={styles.card}>
          <View style={[styles.emojiWrap, { backgroundColor: s.tint + '22', borderColor: s.tint + '44' }]}>
            <Text style={styles.emoji}>{s.emoji}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <View style={styles.labelRow}>
              <Text style={styles.label}>{s.label}</Text>
              {s.live ? <Badge label="In season" tone="accent" dot style={{ marginLeft: spacing.sm }} /> : null}
            </View>
            <Text style={styles.cardSub}>Browse the player pool</Text>
          </View>
          <Ionicons name="chevron-forward" size={22} color={colors.muted} />
        </Card>
      ))}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    heading: { color: colors.text, fontSize: font.titleLg, fontWeight: '800' },
    sub: { color: colors.muted, fontSize: font.body, marginTop: 4, marginBottom: spacing.xl },
    card: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.md },
    emojiWrap: { width: 52, height: 52, borderRadius: 26, borderWidth: 1, alignItems: 'center', justifyContent: 'center', marginRight: spacing.lg },
    emoji: { fontSize: 26 },
    labelRow: { flexDirection: 'row', alignItems: 'center' },
    label: { color: colors.text, fontSize: font.title, fontWeight: '800' },
    cardSub: { color: colors.muted, fontSize: font.small, marginTop: 2 },
  });
