import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { listPlayers } from '../api/sports';
import { useTheme, useThemedStyles, spacing, font } from '../theme';
import { Screen, Card, Avatar, SkeletonList, SectionHeader } from '../components/ui';

export default function GameDetailScreen({ route, navigation }) {
  const { game } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [rosters, setRosters] = useState({ away: [], home: [] });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const [away, home] = await Promise.all([
          listPlayers(token, { sport: 'wnba', team: game.away.abbrev }),
          listPlayers(token, { sport: 'wnba', team: game.home.abbrev }),
        ]);
        if (active) setRosters({ away: away.players, home: home.players });
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [token]);

  function openPlayer(p) {
    navigation.navigate('PlayerProfile', { id: p.id, name: p.name, team: p.team, position: p.position });
  }

  function Roster({ title, players }) {
    return (
      <View style={{ marginTop: spacing.lg }}>
        <SectionHeader style={{ marginTop: 0 }}>{title}</SectionHeader>
        <Card padded={false}>
          {players.length === 0 ? (
            <Text style={styles.emptyRoster}>Roster unavailable.</Text>
          ) : (
            players.map((p, i) => (
              <Pressable
                key={p.id}
                onPress={() => openPlayer(p)}
                style={({ pressed }) => [styles.row, i < players.length - 1 && styles.divider, pressed && { backgroundColor: colors.bgElevated }]}
              >
                <Avatar name={p.name} size={36} />
                <View style={{ flex: 1, marginLeft: spacing.md }}>
                  <Text style={styles.name}>{p.name}</Text>
                  <Text style={styles.meta}>{p.position}</Text>
                </View>
                <Text style={styles.proj}>{Math.round(p.projection)}</Text>
                <Ionicons name="chevron-forward" size={16} color={colors.placeholder} style={{ marginLeft: 8 }} />
              </Pressable>
            ))
          )}
        </Card>
      </View>
    );
  }

  return (
    <Screen scroll>
      <View style={styles.matchup}>
        <Text style={styles.teams}>
          {game.away.abbrev} @ {game.home.abbrev}
        </Text>
        <Text style={styles.sub}>{game.status}</Text>
      </View>

      {loading ? (
        <SkeletonList count={8} />
      ) : (
        <>
          <Roster title={game.away.name} players={rosters.away} />
          <Roster title={game.home.name} players={rosters.home} />
        </>
      )}
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    matchup: { alignItems: 'center', marginBottom: spacing.sm },
    teams: { color: colors.text, fontSize: font.titleLg, fontWeight: '800' },
    sub: { color: colors.muted, fontSize: font.body, marginTop: 4 },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.lg },
    divider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    name: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 1 },
    proj: { color: colors.accent, fontSize: font.bodyLg, fontWeight: '800' },
    emptyRoster: { color: colors.muted, padding: spacing.lg, textAlign: 'center' },
  });
