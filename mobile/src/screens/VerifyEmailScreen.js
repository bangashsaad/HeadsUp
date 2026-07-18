import { useState } from 'react';
import { Alert, StyleSheet, Text } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useThemedStyles, spacing, font } from '../theme';
import { Screen, Field, Button } from '../components/ui';

// Enter the 6-digit code from the signup email. Verifying unlocks challenges.
export default function VerifyEmailScreen({ navigation }) {
  const { user, verifyEmail, resendVerification } = useAuth();
  const styles = useThemedStyles(makeStyles);

  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const codeValid = /^\d{6}$/.test(code.trim());

  async function submit() {
    if (!codeValid) return;
    setSubmitting(true);
    setError(null);
    try {
      await verifyEmail(code.trim());
      Alert.alert('Verified ✅', 'Your email is confirmed — challenges are unlocked.');
      navigation.goBack();
    } catch (e) {
      setError(e.message);
      setSubmitting(false);
    }
  }

  async function resend() {
    setError(null);
    try {
      await resendVerification();
      Alert.alert('Sent', `A fresh code is on its way to ${user?.email}.`);
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <Screen scroll>
      <Text style={styles.intro}>
        We sent a 6-digit code to {user?.email}. Enter it here to unlock creating and accepting duels.
      </Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Field label="Verification code" value={code} onChangeText={setCode} placeholder="123456" keyboardType="number-pad" maxLength={6} autoFocus />

      <Button title="Verify" icon="checkmark-circle" onPress={submit} loading={submitting} disabled={!codeValid} style={{ marginTop: spacing.sm }} />
      <Text style={styles.link} onPress={resend}>
        Didn’t get it? Send a new code
      </Text>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, lineHeight: 21, marginBottom: spacing.lg },
    error: { color: colors.danger, marginBottom: spacing.md, textAlign: 'center' },
    link: { color: colors.accent, textAlign: 'center', marginTop: spacing.lg, fontSize: font.body },
  });
