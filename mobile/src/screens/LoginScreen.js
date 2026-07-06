import { useState } from 'react';
import { KeyboardAvoidingView, Platform, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useThemedStyles, spacing, font } from '../theme';
import { Field, Button } from '../components/ui';
import WordMark from '../components/WordMark';

const EMAIL_RE = /\S+@\S+\.\S+/;

export default function LoginScreen({ navigation }) {
  const { signIn } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const emailValid = EMAIL_RE.test(email.trim());
  const canSubmit = emailValid && password.length > 0;

  async function handleLogin() {
    setError(null);
    setSubmitting(true);
    try {
      await signIn({ email: email.trim(), password });
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={styles.brandWrap}>
        <WordMark size={34} style={{ alignItems: 'center' }} />
      </View>
      <Text style={styles.subtitle}>Log in to challenge your friends</Text>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Field
        value={email}
        onChangeText={setEmail}
        placeholder="Email"
        keyboardType="email-address"
        valid={emailValid}
      />
      <Field value={password} onChangeText={setPassword} placeholder="Password" secure />

      <Button title="Log In" onPress={handleLogin} loading={submitting} disabled={!canSubmit} style={{ marginTop: spacing.sm }} />

      <Text style={styles.link} onPress={() => navigation.navigate('SignUp')}>
        No account? Sign up
      </Text>
    </KeyboardAvoidingView>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    container: { flex: 1, backgroundColor: colors.bg, justifyContent: 'center', padding: 24 },
    brandWrap: { alignItems: 'center', marginBottom: spacing.sm },
    brand: {
      width: 72,
      height: 72,
      borderRadius: 36,
      backgroundColor: colors.accentSoft,
      borderWidth: 1,
      borderColor: colors.accentBorder,
      alignItems: 'center',
      justifyContent: 'center',
    },
    title: { color: colors.text, fontSize: 30, fontWeight: '800', textAlign: 'center' },
    subtitle: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: 6, marginBottom: 28 },
    error: { color: colors.danger, textAlign: 'center', marginBottom: 14, fontSize: font.body },
    link: { color: colors.accent, textAlign: 'center', marginTop: 18, fontSize: font.body },
  });
