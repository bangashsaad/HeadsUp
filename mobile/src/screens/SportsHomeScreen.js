import { ScrollView, StyleSheet, Text, TouchableOpacity } from 'react-native';
import { colors } from '../theme';

const SPORTS = [
  { sport: 'nfl', label: 'Football', emoji: '🏈' },
  { sport: 'nba', label: 'Basketball', emoji: '🏀' },
  { sport: 'wnba', label: 'WNBA', emoji: '🏀' },
  { sport: 'mlb', label: 'Baseball', emoji: '⚾️' },
];

export default function SportsHomeScreen({ navigation }) {
  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.heading}>Pick a sport to browse the player pool</Text>

      {SPORTS.map((s) => (
        <TouchableOpacity
          key={s.sport}
          style={styles.card}
          onPress={() => navigation.navigate('Players', { sport: s.sport, label: s.label })}
        >
          <Text style={styles.emoji}>{s.emoji}</Text>
          <Text style={styles.cardLabel}>{s.label}</Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  content: { padding: 16 },
  heading: { color: colors.muted, fontSize: 15, marginBottom: 16, textAlign: 'center' },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 16,
    padding: 22,
    marginBottom: 14,
  },
  emoji: { fontSize: 34, marginRight: 18 },
  cardLabel: { color: colors.text, fontSize: 22, fontWeight: '700' },
});
