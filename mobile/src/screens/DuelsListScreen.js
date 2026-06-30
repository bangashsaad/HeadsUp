import { useCallback, useState } from 'react';
import { SectionList, StyleSheet, Text, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { listDuels } from '../api/duels';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';
import { Screen, Button, Badge, EmptyState, SkeletonList, FadeIn } from '../components/ui';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

function rowBadge(d) {
  if (d.status === 'settled') {
    if (d.my_outcome === 'win') return { label: 'Won', tone: 'accent' };
    if (d.my_outcome === 'tie') return { label: 'Tie', tone: 'neutral' };
    return { label: 'Lost', tone: 'danger' };
  }
  switch (d.status) {
    case 'drafting':
      return { label: 'Drafting', tone: 'warning' };
    case 'drafted':
      return { label: 'Awaiting', tone: 'info' };
    case 'accepted':
      return { label: 'Ready', tone: 'accent' };
    case 'pending':
      return d.role === 'opponent' ? { label: 'Respond', tone: 'info' } : { label: 'Pending', tone: 'neutral' };
    case 'declined':
      return { label: 'Declined', tone: 'danger' };
    case 'cancelled':
      return { label: 'Cancelled', tone: 'neutral' };
    case 'countered':
      return { label: 'Countered', tone: 'info' };
    default:
      return { label: d.status, tone: 'neutral' };
  }
}

export default function DuelsListScreen({ navigation }) {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duels, setDuels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await listDuels(token);
      setDuels(res.duels);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const sections = buildSections(duels);

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <Button title="New Challenge" icon="add" onPress={() => navigation.navigate('CreateChallenge')} />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <View style={{ marginTop: spacing.md }}>
            <SkeletonList count={5} />
          </View>
        ) : (
          <SectionList
            sections={sections}
            keyExtractor={(item) => String(item.id)}
            stickySectionHeadersEnabled={false}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={{ paddingBottom: spacing.xl, flexGrow: 1 }}
            ListEmptyComponent={
              <EmptyState
                icon="flame-outline"
                title="No challenges yet"
                subtitle="Throw down the gauntlet — challenge a friend to a head-to-head draft."
                action={<Button title="New Challenge" icon="add" onPress={() => navigation.navigate('CreateChallenge')} />}
              />
            }
            renderSectionHeader={({ section }) => (section.data.length ? <Text style={styles.sectionHeader}>{section.title}</Text> : null)}
            renderItem={({ item, index }) => {
              const badge = rowBadge(item);
              return (
                <FadeIn index={index}>
                <Pressable
                  onPress={() => navigation.navigate('DuelDetail', { id: item.id })}
                  style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.card }]}
                >
                  <View style={styles.emojiCircle}>
                    <Text style={styles.emoji}>{SPORT_EMOJI[item.sport] || '🎯'}</Text>
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.vs}>vs {item.opponent.username}</Text>
                    <Text style={styles.meta}>{item.roster_size} players</Text>
                  </View>
                  <Badge label={badge.label} tone={badge.tone} />
                  <Ionicons name="chevron-forward" size={18} color={colors.placeholder} style={{ marginLeft: spacing.sm }} />
                </Pressable>
                </FadeIn>
              );
            }}
          />
        )}
      </View>
    </Screen>
  );
}

function buildSections(duels) {
  const needsResponse = [];
  const waiting = [];
  const active = [];
  const past = [];

  for (const d of duels) {
    if (d.status === 'pending' && d.role === 'opponent') needsResponse.push(d);
    else if (d.status === 'pending' && d.role === 'challenger') waiting.push(d);
    else if (['accepted', 'drafting', 'drafted'].includes(d.status)) active.push(d);
    else past.push(d);
  }

  return [
    { title: 'Needs your response', data: needsResponse },
    { title: 'Waiting on them', data: waiting },
    { title: 'In progress', data: active },
    { title: 'Past', data: past },
  ];
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    sectionHeader: {
      color: colors.muted,
      fontSize: font.caption,
      fontWeight: '800',
      textTransform: 'uppercase',
      letterSpacing: 1,
      marginTop: spacing.lg,
      marginBottom: spacing.xs,
    },
    row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: spacing.sm, borderRadius: radius.md },
    emojiCircle: {
      width: 44,
      height: 44,
      borderRadius: 22,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      alignItems: 'center',
      justifyContent: 'center',
      marginRight: spacing.md,
    },
    emoji: { fontSize: 22 },
    vs: { color: colors.text, fontSize: font.subtitle, fontWeight: '700' },
    meta: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    error: { color: colors.danger, textAlign: 'center', marginTop: spacing.sm },
  });
