import { useState } from 'react';
import { Alert, StyleSheet, Text } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useThemedStyles, spacing, font } from '../theme';
import { Screen, Field, Button } from '../components/ui';

export default function ChangePasswordScreen({ navigation }) {
  const { changePassword } = useAuth();
  const styles = useThemedStyles(makeStyles);

  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const nextValid = next.length >= 8;
  const confirmValid = confirm.length > 0 && confirm === next;
  const canSubmit = current.length > 0 && nextValid && confirmValid;

  async function submit() {
    if (!canSubmit) return;
    setSubmitting(true);
    setError(null);
    try {
      await changePassword({ currentPassword: current, newPassword: next });
      Alert.alert('Password updated', 'Your password has been changed.');
      navigation.goBack();
    } catch (e) {
      setError(e.message);
      setSubmitting(false);
    }
  }

  return (
    <Screen scroll>
      <Text style={styles.intro}>Enter your current password, then choose a new one (at least 8 characters).</Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Field label="Current password" secure value={current} onChangeText={setCurrent} placeholder="Current password" autoFocus />
      <Field
        label="New password"
        secure
        value={next}
        onChangeText={setNext}
        placeholder="At least 8 characters"
        valid={nextValid}
        error={next.length > 0 && !nextValid ? 'Must be at least 8 characters' : null}
      />
      <Field
        label="Confirm new password"
        secure
        value={confirm}
        onChangeText={setConfirm}
        placeholder="Re-enter new password"
        valid={confirmValid}
        error={confirm.length > 0 && !confirmValid ? "Passwords don't match" : null}
      />

      <Button title="Update Password" icon="lock-closed" onPress={submit} loading={submitting} disabled={!canSubmit} style={{ marginTop: spacing.sm }} />
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, lineHeight: 21, marginBottom: spacing.lg },
    error: { color: colors.danger, marginBottom: spacing.md, textAlign: 'center' },
  });
