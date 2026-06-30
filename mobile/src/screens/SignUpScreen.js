import { useState } from 'react';
import { KeyboardAvoidingView, Platform, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { useTheme, useThemedStyles, spacing, font } from '../theme';
import { Field, Button } from '../components/ui';

const EMAIL_RE = /\S+@\S+\.\S+/;
const USERNAME_RE = /^[a-zA-Z0-9_]{3,20}$/;

export default function SignUpScreen({ navigation }) {
  const { signUp } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const usernameValid = USERNAME_RE.test(username.trim());
  const emailValid = EMAIL_RE.test(email.trim());
  const passwordValid = password.length >= 8;
  const canSubmit = usernameValid && emailValid && passwordValid;

  async function handleSignUp() {
    setError(null);
    setSubmitting(true);
    try {
      await signUp({ username: username.trim(), email: email.trim(), password });
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={styles.brandWrap}>
        <View style={styles.brand}>
          <Ionicons name="flame" size={34} color={colors.accent} />
        </View>
      </View>
      <Text style={styles.title}>Create your account</Text>
      <Text style={styles.subtitle}>Pick a username your buddies will know you by</Text>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Field
        value={username}
        onChangeText={setUsername}
        placeholder="Username"
        valid={usernameValid}
        error={username.length > 0 && !usernameValid ? '3–20 letters, numbers or underscores' : null}
      />
      <Field value={email} onChangeText={setEmail} placeholder="Email" keyboardType="email-address" valid={emailValid} />
      <Field
        value={password}
        onChangeText={setPassword}
        placeholder="Password (8+ characters)"
        secure
        valid={passwordValid}
        error={password.length > 0 && !passwordValid ? 'At least 8 characters' : null}
      />

      <Button title="Sign Up" onPress={handleSignUp} loading={submitting} disabled={!canSubmit} style={{ marginTop: spacing.sm }} />

      <Text style={styles.link} onPress={() => navigation.navigate('Login')}>
        Already have an account? Log in
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
