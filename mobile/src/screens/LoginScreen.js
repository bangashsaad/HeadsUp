import { useState } from 'react';
import { KeyboardAvoidingView, Platform, Text, TextInput, View, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { authStyles as s, colors } from '../theme';
import { Button } from '../components/ui';

export default function LoginScreen({ navigation }) {
  const { signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);

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
    <KeyboardAvoidingView style={s.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={styles.brandWrap}>
        <View style={styles.brand}>
          <Ionicons name="flame" size={34} color={colors.accent} />
        </View>
      </View>
      <Text style={s.title}>Heads Up</Text>
      <Text style={s.subtitle}>Log in to challenge your friends</Text>

      {error ? <Text style={s.error}>{error}</Text> : null}

      <TextInput
        style={s.input}
        placeholder="Email"
        placeholderTextColor={colors.placeholder}
        autoCapitalize="none"
        autoCorrect={false}
        keyboardType="email-address"
        value={email}
        onChangeText={setEmail}
      />
      <TextInput
        style={s.input}
        placeholder="Password"
        placeholderTextColor={colors.placeholder}
        secureTextEntry
        value={password}
        onChangeText={setPassword}
      />

      <Button title="Log In" onPress={handleLogin} loading={submitting} style={{ marginTop: 8 }} />

      <Text style={s.link} onPress={() => navigation.navigate('SignUp')}>
        No account? Sign up
      </Text>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  brandWrap: { alignItems: 'center', marginBottom: 8 },
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
});
