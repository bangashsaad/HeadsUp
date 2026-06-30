import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Card, Avatar, Button } from '../components/ui';

function Row({ icon, label, sublabel, onPress, danger }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.bgElevated }]}>
      <View style={[styles.rowIcon, danger && { backgroundColor: colors.dangerSoft }]}>
        <Ionicons name={icon} size={18} color={danger ? colors.danger : colors.accent} />
      </View>
      <View style={{ flex: 1 }}>
        <Text style={[styles.rowLabel, danger && { color: colors.danger }]}>{label}</Text>
        {sublabel ? <Text style={styles.rowSub}>{sublabel}</Text> : null}
      </View>
      <Ionicons name="chevron-forward" size={18} color={colors.placeholder} />
    </Pressable>
  );
}

export default function ProfileScreen({ navigation }) {
  const { user, signOut } = useAuth();
  const styles = useThemedStyles(makeStyles);

  function howToPlay() {
    Alert.alert(
      'How to play',
      'Challenge a friend to a 1-on-1 fantasy duel: agree on the sport, lineup and scoring, draft your roster live (snake order, ticking clock), then the winner is declared automatically once the games finish.'
    );
  }

  return (
    <Screen scroll>
      <Card style={styles.headerCard}>
        <Avatar name={user?.username || '?'} size={72} />
        <Text style={styles.username}>{user?.username}</Text>
        {user?.email ? <Text style={styles.email}>{user.email}</Text> : null}
      </Card>

      <Card padded={false} style={{ marginTop: spacing.lg }}>
        <Row icon="settings-outline" label="Settings" sublabel="Appearance, preferences, account" onPress={() => navigation.navigate('Settings')} />
        <View style={styles.divider} />
        <Row icon="help-circle-outline" label="How to play" onPress={howToPlay} />
      </Card>

      <View style={{ marginTop: spacing.xl }}>
        <Button title="Log Out" variant="danger" icon="log-out-outline" onPress={signOut} />
      </View>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerCard: { alignItems: 'center', paddingVertical: spacing.xl },
    username: { color: colors.text, fontSize: font.title, fontWeight: '800', marginTop: spacing.md },
    email: { color: colors.muted, fontSize: font.body, marginTop: 2 },
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
    divider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle, marginLeft: 60 },
  });
