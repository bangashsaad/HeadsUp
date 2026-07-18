import { useState } from 'react';
import { Alert, StyleSheet, Text } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useThemedStyles, spacing, font } from '../theme';
import { Screen, Field, Button } from '../components/ui';

// Two steps on one screen: ask for the email, then trade the emailed 6-digit
// code + a new password. The server never says whether an email exists.
export default function ForgotPasswordScreen({ navigation }) {
  const { forgotPassword, resetPassword } = useAuth();
  const styles = useThemedStyles(makeStyles);

  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const emailValid = /.+@.+\..+/.test(email.trim());
  const codeValid = /^\d{6}$/.test(code.trim());
  const passwordValid = password.length >= 8;

  async function requestCode() {
    if (!emailValid) return;
    setSubmitting(true);
    setError(null);
    try {
      await forgotPassword(email.trim().toLowerCase());
      setSent(true);
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  async function submitReset() {
    if (!codeValid || !passwordValid) return;
    setSubmitting(true);
    setError(null);
    try {
      await resetPassword({ email: email.trim().toLowerCase(), code: code.trim(), password });
      Alert.alert('Password reset', 'You’re set — log in with your new password.');
      navigation.goBack();
    } catch (e) {
      setError(e.message);
      setSubmitting(false);
    }
  }

  return (
    <Screen scroll>
      {!sent ? (
        <>
          <Text style={styles.intro}>
            Enter your account email — if it exists, we’ll send a 6-digit reset code.
          </Text>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          <Field
            label="Email"
            value={email}
            onChangeText={setEmail}
            placeholder="you@example.com"
            autoCapitalize="none"
            keyboardType="email-address"
            autoFocus
          />
          <Button title="Send Code" icon="mail" onPress={requestCode} loading={submitting} disabled={!emailValid} style={{ marginTop: spacing.sm }} />
        </>
      ) : (
        <>
          <Text style={styles.intro}>
            Check {email.trim()} for a 6-digit code (it expires in 15 minutes), then choose a new password.
          </Text>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          <Field
            label="Reset code"
            value={code}
            onChangeText={setCode}
            placeholder="123456"
            keyboardType="number-pad"
            maxLength={6}
            autoFocus
          />
          <Field
            label="New password"
            secure
            value={password}
            onChangeText={setPassword}
            placeholder="At least 8 characters"
            valid={passwordValid}
            error={password.length > 0 && !passwordValid ? 'Must be at least 8 characters' : null}
          />
          <Button
            title="Reset Password"
            icon="lock-closed"
            onPress={submitReset}
            loading={submitting}
            disabled={!codeValid || !passwordValid}
            style={{ marginTop: spacing.sm }}
          />
          <Text style={styles.link} onPress={requestCode}>
            Didn’t get it? Send a new code
          </Text>
        </>
      )}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, lineHeight: 21, marginBottom: spacing.lg },
    error: { color: colors.danger, marginBottom: spacing.md, textAlign: 'center' },
    link: { color: colors.accent, textAlign: 'center', marginTop: spacing.lg, fontSize: font.body },
  });
