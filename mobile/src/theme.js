import { StyleSheet } from 'react-native';

// One place for our app's colors, so the whole app stays consistent.
export const colors = {
  bg: '#0f172a',
  card: '#1e293b',
  border: '#334155',
  text: '#ffffff',
  muted: '#94a3b8',
  placeholder: '#64748b',
  accent: '#4ade80',
  danger: '#f87171',
};

// Shared dark styling for navigation headers.
export const navHeader = {
  headerStyle: { backgroundColor: colors.bg },
  headerTintColor: colors.text,
  headerShadowVisible: false,
};

// Shared styles for the Login and Sign Up screens (they look the same).
export const authStyles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
    justifyContent: 'center',
    padding: 24,
  },
  title: { color: colors.text, fontSize: 30, fontWeight: '800', textAlign: 'center' },
  subtitle: {
    color: colors.muted,
    fontSize: 15,
    textAlign: 'center',
    marginTop: 6,
    marginBottom: 28,
  },
  input: {
    backgroundColor: colors.card,
    color: colors.text,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  button: {
    backgroundColor: colors.accent,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonText: { color: colors.bg, fontSize: 16, fontWeight: '700' },
  link: { color: colors.accent, textAlign: 'center', marginTop: 18, fontSize: 15 },
  error: { color: colors.danger, textAlign: 'center', marginBottom: 14, fontSize: 14 },
});
