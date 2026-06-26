import { useState } from 'react';
import { ScrollView, StyleSheet, Text } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { counterChallenge } from '../api/duels';
import ChallengeForm from '../components/ChallengeForm';
import { colors } from '../theme';

export default function CounterScreen({ route, navigation }) {
  const { id, initial } = route.params;
  const { token } = useAuth();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  async function submit(terms) {
    setSubmitting(true);
    setError(null);
    try {
      const res = await counterChallenge(token, id, terms);
      // The counter creates a NEW duel going the other way — show it.
      navigation.replace('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setError(e.message);
      setSubmitting(false);
    }
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ padding: 16 }}>
      <Text style={styles.intro}>
        Change the terms and send it back. They'll get a new challenge to accept, decline, or
        counter again.
      </Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <ChallengeForm
        initial={initial}
        onSubmit={submit}
        submitLabel="Send Counter"
        submitting={submitting}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  intro: { color: colors.muted, fontSize: 14, lineHeight: 20, marginBottom: 6 },
  error: { color: colors.danger, textAlign: 'center', marginTop: 12 },
});
