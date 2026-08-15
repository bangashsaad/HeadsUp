# Settings — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Theme (dark/light/system) and account controls.

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

## The screen source (`src/screens/SettingsScreen.js`)

```jsx
import { Alert, Platform, Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Constants from 'expo-constants';
import { useAuth } from '../auth/AuthContext';
import { usePrefs } from '../prefs';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, SectionHeader, Button } from '../components/ui';

const APPEARANCE = [
  { key: 'system', label: 'System', icon: 'phone-portrait-outline' },
  { key: 'light', label: 'Light', icon: 'sunny-outline' },
  { key: 'dark', label: 'Dark', icon: 'moon-outline' },
];

export default function SettingsScreen({ navigation }) {
  const { colors, mode, setMode } = useTheme();
  const { haptics, setHaptics } = usePrefs();
  const { signOut, deleteAccount } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const version = Constants.expoConfig?.version || '1.0.0';

  function confirmDelete() {
    Alert.alert(
      'Delete your account?',
      'This is permanent. Your profile is erased, live duels are cancelled and every stake is refunded. Finished duels stay in your friends’ history under an anonymous name.',
      [
        { text: 'Keep my account', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: askPassword },
      ]
    );
  }

  function askPassword() {
    if (Platform.OS !== 'ios') {
      Alert.alert('Not available', 'Account deletion is currently iOS-only — contact support.');
      return;
    }
    Alert.prompt(
      'Confirm with your password',
      'Enter your password to permanently delete this account.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete forever',
          style: 'destructive',
          onPress: (password) => {
            deleteAccount(password || '').catch((e) =>
              Alert.alert('Couldn’t delete', e?.message || 'Check your password and try again.')
            );
          },
        },
      ],
      'secure-text'
    );
  }

  return (
    <Screen scroll>
      <SectionHeader style={{ marginTop: 0 }}>Appearance</SectionHeader>
      <Card padded={false} style={{ padding: spacing.xs }}>
        <View style={styles.segment}>
          {APPEARANCE.map((opt) => {
            const active = mode === opt.key;
            return (
              <Pressable key={opt.key} onPress={() => setMode(opt.key)} style={[styles.segItem, active && styles.segItemActive]}>
                <Ionicons name={opt.icon} size={18} color={active ? colors.onAccent : colors.muted} />
                <Text style={[styles.segLabel, { color: active ? colors.onAccent : colors.muted }]}>{opt.label}</Text>
              </Pressable>
            );
          })}
        </View>
      </Card>

      <SectionHeader>Preferences</SectionHeader>
      <Card padded={false}>
        <View style={styles.row}>
          <View style={styles.rowIcon}>
            <Ionicons name="pulse" size={18} color={colors.accent} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.rowLabel}>Haptic feedback</Text>
            <Text style={styles.rowSub}>Vibrations on taps, picks and results</Text>
          </View>
          <Switch value={haptics} onValueChange={setHaptics} trackColor={{ true: colors.accent, false: colors.border }} thumbColor="#ffffff" />
        </View>
      </Card>

      <SectionHeader>Account</SectionHeader>
      <Card padded={false}>
        <Pressable onPress={() => navigation.navigate('ChangePassword')} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
          <View style={styles.rowIcon}>
            <Ionicons name="lock-closed-outline" size={18} color={colors.accent} />
          </View>
          <Text style={[styles.rowLabel, { flex: 1 }]}>Change password</Text>
          <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
        </Pressable>
        <Pressable onPress={confirmDelete} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
          <View style={[styles.rowIcon, { backgroundColor: colors.dangerSoft }]}>
            <Ionicons name="trash-outline" size={18} color={colors.danger} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={[styles.rowLabel, { color: colors.danger }]}>Delete account</Text>
            <Text style={styles.rowSub}>Permanent — live duels cancel, stakes refund</Text>
          </View>
          <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
        </Pressable>
      </Card>

      <SectionHeader>About</SectionHeader>
      <Card>
        <View style={styles.aboutRow}>
          <Text style={styles.aboutLabel}>Version</Text>
          <Text style={styles.aboutValue}>{version}</Text>
        </View>
        <View style={[styles.aboutRow, { marginTop: spacing.sm }]}>
          <Text style={styles.aboutLabel}>App</Text>
          <Text style={styles.aboutValue}>Heads Up Fantasy</Text>
        </View>
      </Card>

      <View style={{ marginTop: spacing.xl }}>
        <Button title="Log Out" variant="danger" icon="log-out-outline" onPress={signOut} />
      </View>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    segment: { flexDirection: 'row', gap: spacing.xs },
    segItem: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 12, borderRadius: radius.md },
    segItemActive: { backgroundColor: colors.accent },
    segLabel: { fontSize: font.small, fontWeight: '700' },
    row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: spacing.lg, paddingVertical: spacing.md },
    rowIcon: {
      width: 34,
      height: 34,
      borderRadius: 10,
      backgroundColor: colors.accentSoft,
      alignItems: 'center',
      justifyContent: 'center',
      marginRight: spacing.md,
    },
    rowLabel: { color: colors.text, fontSize: font.bodyLg, fontWeight: '600' },
    rowSub: { color: colors.muted, fontSize: font.small, marginTop: 1 },
    aboutRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
    aboutLabel: { color: colors.muted, fontSize: font.body },
    aboutValue: { color: colors.text, fontSize: font.body, fontWeight: '600' },
  });
```
