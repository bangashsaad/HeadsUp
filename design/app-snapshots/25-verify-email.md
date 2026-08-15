# Verify email — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

The 6-digit code gate — unverified accounts get bounced here before they can duel. Auto-sends the code, resend link.

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

## The screen source (`src/screens/VerifyEmailScreen.js`)

```jsx
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
```
