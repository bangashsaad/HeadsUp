import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { getPlayerProfile } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Card, Avatar, Badge, EmptyState, SkeletonList } from '../components/ui';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function shortDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

export default function PlayerProfileScreen({ route }) {
  const { id, name, team, position } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await getPlayerProfile(token, id);
        if (active) setProfile(res);
      } catch (e) {
        if (active) setError(e.message);
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [token, id]);

  const header = (
    <View style={styles.header}>
      <Avatar name={name || profile?.player?.name || '?'} size={64} />
      <View style={{ marginLeft: spacing.lg, flex: 1 }}>
        <Text style={styles.name}>{name || profile?.player?.name}</Text>
        <Text style={styles.sub}>
          {(team || profile?.player?.team) ?? ''} · {(position || profile?.player?.position) ?? ''}
        </Text>
      </View>
    </View>
  );

  if (loading) {
    return (
      <Screen>
        {header}
        <SkeletonList count={6} />
      </Screen>
    );
  }

  if (error) {
    return (
      <Screen>
        {header}
        <EmptyState icon="alert-circle-outline" title="Couldn't load stats" subtitle={error} />
      </Screen>
    );
  }

  if (!profile?.available) {
    return (
      <Screen>
        {header}
        <EmptyState
          icon="stats-chart-outline"
          title="Stats coming soon"
          subtitle="Live stats are available for WNBA and MLB players right now. Other leagues are on the way."
        />
      </Screen>
    );
  }

  const s = profile.season || {};
  const tiles = s.tiles || [];

  return (
    <Screen scroll>
      {header}

      <Card style={styles.avgCard}>
        <View style={styles.avgGrid}>
          {tiles.map((t) => (
            <Stat key={t.label} label={t.label} value={t.value} accent={t.label === 'FPG'} styles={styles} />
          ))}
        </View>
        <Text style={styles.avgNote}>Season totals & averages over {s.games_played ?? 0} games</Text>
      </Card>

      <Text style={styles.logTitle}>Game log</Text>
      {(profile.games || []).length === 0 ? (
        <EmptyState icon="calendar-outline" title="No games yet" subtitle="This player hasn't logged a game this season." />
      ) : (
        <Card padded={false}>
          {profile.games.map((g, i) => (
            <View key={g.event_id} style={[styles.gameRow, i < profile.games.length - 1 && styles.gameDivider]}>
              <View style={{ flex: 1 }}>
                <View style={styles.gameTop}>
                  <Text style={styles.gameDate}>{shortDate(g.date)}</Text>
                  <Text style={styles.gameMatch}>
                    {g.home_away === '@' ? '@' : 'vs'} {g.opponent}
                  </Text>
                  {g.result ? (
                    <Badge label={g.result} tone={g.result === 'W' ? 'accent' : 'danger'} />
                  ) : null}
                </View>
                <Text style={styles.gameBox}>{g.line}</Text>
              </View>
              <View style={styles.fanWrap}>
                <Text style={styles.fanValue}>{g.fantasy}</Text>
                <Text style={styles.fanLabel}>FAN</Text>
              </View>
            </View>
          ))}
        </Card>
      )}
    </Screen>
  );
}

function Stat({ label, value, accent, styles }) {
  return (
    <View style={styles.stat}>
      <Text style={[styles.statValue, accent && styles.statAccent]}>{value ?? '—'}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg },
    name: { color: colors.text, fontSize: 26, fontFamily: fonts.hero, paddingRight: 4 },
    sub: { color: colors.muted, fontSize: font.body, marginTop: 2 },
    avgCard: { marginBottom: spacing.lg },
    avgGrid: { flexDirection: 'row', justifyContent: 'space-between' },
    stat: { alignItems: 'center', flex: 1 },
    statValue: { color: colors.text, fontSize: 24, fontFamily: fonts.hero },
    statAccent: { color: colors.accent },
    statLabel: { color: colors.muted, fontSize: 10, fontWeight: '700', letterSpacing: 0.5, marginTop: 2 },
    avgNote: { color: colors.placeholder, fontSize: font.caption, textAlign: 'center', marginTop: spacing.md },
    logTitle: { color: colors.text, fontSize: font.bodyLg, fontWeight: '700', marginBottom: spacing.sm },
    gameRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: spacing.lg },
    gameDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    gameTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    gameDate: { color: colors.muted, fontSize: font.small, fontWeight: '700', width: 48 },
    gameMatch: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    gameBox: { color: colors.muted, fontSize: font.caption, marginTop: 4 },
    fanWrap: { alignItems: 'center', marginLeft: spacing.md },
    fanValue: { color: colors.accent, fontSize: 19, fontFamily: fonts.hero },
    fanLabel: { color: colors.placeholder, fontSize: 9, fontWeight: '700', letterSpacing: 0.5 },
  });
