import { StyleSheet } from 'react-native';

// One place for our app's colors, so the whole app stays consistent.
export const colors = {
  // surfaces (low -> high elevation)
  bg: '#0f172a',
  bgElevated: '#162136',
  card: '#1e293b',
  cardElevated: '#243349',
  // lines
  border: '#334155',
  borderSubtle: '#28344a',
  // text
  text: '#ffffff',
  muted: '#94a3b8',
  placeholder: '#64748b',
  // brand + semantic
  accent: '#4ade80',
  accentSoft: 'rgba(74,222,128,0.12)',
  accentBorder: 'rgba(74,222,128,0.35)',
  danger: '#f87171',
  dangerSoft: 'rgba(248,113,113,0.12)',
  warning: '#fbbf24',
  warningSoft: 'rgba(251,191,36,0.12)',
  info: '#60a5fa',
  infoSoft: 'rgba(96,165,250,0.12)',
};

// Spacing scale — use these instead of magic numbers so rhythm stays even.
export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 };

// Corner radii.
export const radius = { sm: 8, md: 12, lg: 16, xl: 20, pill: 999 };

// Type scale (size + a sensible default weight intent left to the caller).
export const font = {
  caption: 12,
  small: 13,
  body: 15,
  bodyLg: 16,
  subtitle: 17,
  title: 22,
  titleLg: 28,
  hero: 34,
};

// Drop shadows for depth (iOS shadow* + Android elevation).
export const shadow = {
  sm: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.18, shadowRadius: 6, elevation: 2 },
  md: { shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.22, shadowRadius: 12, elevation: 5 },
  lg: { shadowColor: '#000', shadowOffset: { width: 0, height: 8 }, shadowOpacity: 0.3, shadowRadius: 20, elevation: 10 },
  accent: { shadowColor: '#4ade80', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.35, shadowRadius: 14, elevation: 6 },
};

// Semantic tone -> {bg, text, border} for status pills, banners, badges.
// Centralizes the colors that used to be hardcoded inside DuelDetail/Results.
export const tones = {
  neutral: { bg: colors.card, text: colors.muted, border: colors.border },
  accent: { bg: colors.accentSoft, text: colors.accent, border: colors.accentBorder },
  danger: { bg: colors.dangerSoft, text: colors.danger, border: 'rgba(248,113,113,0.35)' },
  warning: { bg: colors.warningSoft, text: colors.warning, border: 'rgba(251,191,36,0.35)' },
  info: { bg: colors.infoSoft, text: colors.info, border: 'rgba(96,165,250,0.35)' },
};

// Map a duel status string to a tone name.
export function statusTone(status) {
  switch (status) {
    case 'accepted':
    case 'drafted':
    case 'settled':
      return 'accent';
    case 'drafting':
      return 'warning';
    case 'pending':
    case 'countered':
      return 'info';
    case 'declined':
    case 'cancelled':
      return 'danger';
    default:
      return 'neutral';
  }
}

// Deterministic avatar tint from a name, so each person keeps a stable color.
const AVATAR_TINTS = ['#4ade80', '#60a5fa', '#fbbf24', '#f472b6', '#a78bfa', '#22d3ee', '#fb923c'];
export function avatarColor(seed = '') {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return AVATAR_TINTS[h % AVATAR_TINTS.length];
}

// Shared dark styling for navigation headers.
export const navHeader = {
  headerStyle: { backgroundColor: colors.bg },
  headerTintColor: colors.text,
  headerShadowVisible: false,
  headerTitleStyle: { fontWeight: '800' },
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
