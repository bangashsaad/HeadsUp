# Sign up — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Username, email, password → 1,000-coin signup grant.

## The app's design language (real tokens, from `src/theme.js`)

Dark palette (the shipped look): bg `#0A0B10`, elevated `#0D0F16`, card `#12141D`,
card-elevated `#191C28`, border `#252A3A`, subtle border `#1A1E2B`, text `#F4F5F7`,
dim `#B9BECF`, muted `#8B91A7`, placeholder `#565D73`, **accent lime `#C8FF2E`**
(text on accent: `#0A0B10`), danger `#FF4557`, warning/gold `#FFB021`,
purple `#7C5CFF` (text `#9F8BFF`), cyan `#22E5FF`, pink `#FF4D8D`, green `#39D98A`.
A light palette exists too; dark is the default and the brand.

Type: **Archivo** (body, weights 400–900), **Archivo Black italic** (display —
wordmark, "YOU WIN.", ghost VS), **Barlow Condensed 800 italic** (hero — scores,
section titles, ALL-CAPS pill buttons). Shapes: 999px pill buttons/chips,
8/12/16/20px card radii, 1px borders. Status→color: drafting = red (blinks),
pending/countered = purple, accepted/settled = lime, live dots blink.

UI kit primitives the screens compose (from `src/components/ui/`):

- **Avatar** — Initials tile with a stable per-name tint. Rounded square ("squircle"), per the Reimagined language. (8-digit hex appends alpha.)
- **Badge** — Small uppercase status pill. `tone` is one of the keys in theme `tones`. `dot` shows a leading dot; `blink` makes it pulse (live things blink).
- **BlinkDot** — The little live dot. blink=false renders it steady.
- **Button** — Condensed-italic pill buttons — the Reimagined CTA voice (ENTER ROOM →).
- **Card** — A surface with depth — border + soft shadow. Pass onPress to make it tappable.
- **Chip** — A selectable pill (filters, toggles). Light selection haptic on tap. Mirrors the Segmented recipe: center the label and let Barlow Condensed keep its NATURAL line height — forcing a lineHeight clips the glyphs on iOS.
- **EmptyState** — Friendly centered placeholder: an icon coin, a title, a subtitle, and an optional action node (e.g. a Button).
- **FadeIn** — Fade + slide a list row in on mount, lightly staggered by its index.
- **Field** — Labeled text input with optional password show/hide, a valid ✓, and an error.
- **GhostText** — Outline-only display text — the big translucent "VS" / pick-number watermarks. Rendered as stroked SVG text (RN has no text-stroke). Defaults to a faint stroke of the theme's text color, so it reads in light mode too.
- **Marquee** — Endless horizontal ticker: renders `children` twice and slides one copy's width, looping seamlessly. `speed` is px/second.
- **Pulse** — A soft expanding halo behind its children — the design's pulsing CTA ring.
- **Screen** — Page wrapper: themed bg, keyboard avoidance, and an optional scroll view with pull-to-refresh. No safe-area insets by default (the header owns the top, the tab bar owns the bottom).
- **SearchInput** — Text field with a leading search icon and a clear (×) button.
- **SectionHeader** — Condensed-italic section title, e.g. "YOUR MOVE", with an optional right hint ("3 PENDING"). Accepts a plain string child for back-compat.
- **Segmented** — The ACTIVE | PAST switch: a recessed track with a lime active segment. options: [{ key, label, count }]
- **Skeleton** — A single pulsing placeholder bar.
- **StatTile** — One tile of the 4-up stat grid: big condensed-italic value over a tiny kicker.
- **Type** — The three voices of the Reimagined type system. Tiny 800-weight uppercase tracking label: "SEASON RECORD", "PICK 3 OF 10".

## The screen source (`src/screens/SignUpScreen.js`)

```jsx
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useThemedStyles, spacing, font, fonts } from '../theme';
import { Field, Button } from '../components/ui';
import WordMark from '../components/WordMark';

const EMAIL_RE = /\S+@\S+\.\S+/;
const USERNAME_RE = /^[a-zA-Z0-9_]{3,20}$/;

export default function SignUpScreen({ navigation }) {
  const { signUp } = useAuth();
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
        <WordMark size={26} tag={false} style={{ alignItems: 'center' }} />
      </View>
      <Text style={styles.title}>CREATE YOUR ACCOUNT</Text>
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
    title: { color: colors.text, fontSize: 24, fontFamily: fonts.hero, letterSpacing: 0.5, textAlign: 'center' },
    subtitle: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: 6, marginBottom: 28 },
    error: { color: colors.danger, textAlign: 'center', marginBottom: 14, fontSize: font.body },
    link: { color: colors.accent, textAlign: 'center', marginTop: 18, fontSize: font.body },
  });
```

## Shared component it uses: `WordMark.js`

```jsx
import { View, Text } from 'react-native';
import { useTheme, fonts } from '../theme';

// The brand lockup: HEADS(text)UP(lime) in Archivo Black italic, with the
// "FANTASY DUELS" tag underneath when `tag` is true.
export default function WordMark({ size = 21, tag = true, style }) {
  const { colors } = useTheme();
  return (
    <View style={style}>
      <Text style={{ fontFamily: fonts.display, fontSize: size, letterSpacing: -0.5, lineHeight: size * 1.05 }}>
        <Text style={{ color: colors.text }}>HEADS</Text>
        <Text style={{ color: colors.accent }}>UP</Text>
      </Text>
      {tag ? (
        <Text
          style={{
            fontSize: Math.max(7.5, size * 0.4),
            fontFamily: fonts.bodyExtra,
            letterSpacing: 3.5,
            color: colors.placeholder,
            marginTop: 3,
          }}
        >
          FANTASY DUELS
        </Text>
      ) : null}
    </View>
  );
}
```
