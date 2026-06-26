import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Text,
  TextInput,
  TouchableOpacity,
} from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { authStyles as s, colors } from '../theme';

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
      // On success, the app automatically switches to the Home screen.
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <KeyboardAvoidingView
      style={s.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <Text style={s.title}>Heads Up Fantasy</Text>
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

      <TouchableOpacity style={s.button} onPress={handleLogin} disabled={submitting}>
        {submitting ? (
          <ActivityIndicator color={colors.bg} />
        ) : (
          <Text style={s.buttonText}>Log In</Text>
        )}
      </TouchableOpacity>

      <TouchableOpacity onPress={() => navigation.navigate('SignUp')}>
        <Text style={s.link}>No account? Sign up</Text>
      </TouchableOpacity>
    </KeyboardAvoidingView>
  );
}
