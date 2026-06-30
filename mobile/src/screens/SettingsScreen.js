import { Pressable, StyleSheet, Switch, Text, View } from 'react-native';
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
  const { signOut } = useAuth();
  const styles = useThemedStyles(makeStyles);
  const version = Constants.expoConfig?.version || '1.0.0';

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
