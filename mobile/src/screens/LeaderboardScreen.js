import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getLeaderboard } from '../api/me';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Avatar, EmptyState, SkeletonList } from '../components/ui';

const MEDAL = { 1: '🥇', 2: '🥈', 3: '🥉' };

export default function LeaderboardScreen() {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [rows, setRows] = useState(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      getLeaderboard(token)
        .then((r) => active && setRows(r.leaderboard || []))
        .catch(() => active && setRows([]));
      return () => {
        active = false;
      };
    }, [token])
  );

  if (rows === null) {
    return (
      <Screen>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  return (
    <Screen padded={false}>
      <FlatList
        data={rows}
        keyExtractor={(item) => String(item.user.id)}
        contentContainerStyle={{ padding: spacing.lg }}
        ListHeaderComponent={<Text style={styles.intro}>Standings among you and your friends, by wins.</Text>}
        ListEmptyComponent={<EmptyState icon="podium-outline" title="The podium is empty" subtitle="Win a duel and plant your flag at #1." />}
        renderItem={({ item }) => {
          const me = item.user.id === user?.id;
          return (
            <View style={[styles.row, me && styles.meRow]}>
              <Text style={styles.rank}>{MEDAL[item.rank] || item.rank}</Text>
              <Avatar name={item.user.username} size={36} />
              <View style={{ flex: 1, marginLeft: spacing.md }}>
                <Text style={[styles.name, me && { color: colors.accent }]}>
                  {item.user.username}
                  {me ? ' (you)' : ''}
                </Text>
                <Text style={styles.sub}>
                  {item.played} played · {Math.round((item.win_pct || 0) * 100)}% win
                </Text>
              </View>
              <Text style={styles.record}>
                {item.wins}-{item.losses}
                {item.ties ? `-${item.ties}` : ''}
              </Text>
            </View>
          );
        }}
      />
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: font.body, marginBottom: spacing.md },
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      borderRadius: radius.md,
      padding: spacing.md,
      marginBottom: spacing.sm,
    },
    meRow: { borderColor: colors.accentBorder },
    rank: { color: colors.text, fontSize: 17, fontFamily: fonts.hero, width: 30, textAlign: 'center', marginRight: spacing.sm },
    name: { color: colors.text, fontSize: font.subtitle, fontWeight: '700' },
    sub: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    record: { color: colors.text, fontSize: 17, fontFamily: fonts.heroUpright },
  });
