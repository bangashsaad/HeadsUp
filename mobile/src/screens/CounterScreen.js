import { useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { counterChallenge } from '../api/duels';
import ChallengeForm from '../components/ChallengeForm';
import { useThemedStyles, spacing, font } from '../theme';
import { Screen, Card } from '../components/ui';

export default function CounterScreen({ route, navigation }) {
  const { id, initial } = route.params;
  const { token, refreshUser } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  async function submit(terms) {
    setSubmitting(true);
    setError(null);
    try {
      const res = await counterChallenge(token, id, terms);
      refreshUser(); // old stake refunded, new stake escrowed
      navigation.replace('DuelDetail', { id: res.duel.id });
    } catch (e) {
      setError(e.message);
      setSubmitting(false);
    }
  }

  return (
    <Screen scroll>
      <Card style={{ marginBottom: spacing.md }}>
        <Text style={styles.intro}>
          Change the terms and send it back. They'll get a new challenge to accept, decline, or counter again.
        </Text>
      </Card>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <ChallengeForm initial={initial} onSubmit={submit} submitLabel="Send Counter" submitting={submitting} />
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, lineHeight: 21 },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.md },
  });
