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

function rowTitle(d) {
  if (!d.group) return `vs ${d.opponent?.username || 'Opponent'}`;
  if (d.role === 'challenger') return `Your ${d.party_size}-player match`;
  return `${d.opponent?.username || 'A friend'}'s ${d.party_size}-player match`;
}

function rowMeta(d) {
  if (d.group && d.status === 'pending') {
    const seated = (d.participants || []).filter((p) => p.status === 'accepted').length;
    return `${seated}/${d.party_size} in · ${d.roster_size} rounds`;
  }
  return `${d.roster_size} rounds`;
}

const ACTIVE_STATES = ['pending', 'accepted', 'drafting', 'drafted', 'countered'];

function partition(duels) {
  const active = duels.filter((d) => ACTIVE_STATES.includes(d.status));
  const past = duels.filter((d) => !ACTIVE_STATES.includes(d.status));
  return { active, past };
}

function activeSections(active) {
  const needsResponse = active.filter((d) => d.status === 'pending' && d.role === 'opponent');
  const waiting = active.filter((d) => d.status === 'pending' && d.role === 'challenger');
  const inProgress = active.filter((d) => ['accepted', 'drafting', 'drafted', 'countered'].includes(d.status));
  return [
    { title: 'Needs your response', data: needsResponse },
    { title: 'Waiting on them', data: waiting },
    { title: 'In progress', data: inProgress },
  ];
}

function pastSections(past) {
  const completed = past.filter((d) => d.status === 'settled');
  const other = past.filter((d) => d.status !== 'settled');
  return [
    { title: 'Completed', data: completed },
    { title: 'Declined & cancelled', data: other },
  ];
}

export default function DuelsListScreen({ navigation }) {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duels, setDuels] = useState([]);
  const [tab, setTab] = useState('active');
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

  const { active, past } = partition(duels);
  const sections = tab === 'active' ? activeSections(active) : pastSections(past);

  return (
    <Screen padded={false}>
      <View style={styles.body}>
        <Button title="New Challenge" icon="add" onPress={() => navigation.navigate('CreateChallenge')} />

        <View style={styles.segment}>
          <SegTab label="Active" count={active.length} on={tab === 'active'} onPress={() => setTab('active')} styles={styles} colors={colors} />
          <SegTab label="Past" count={past.length} on={tab === 'past'} onPress={() => setTab('past')} styles={styles} colors={colors} />
        </View>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        {loading ? (
          <SkeletonList count={5} />
        ) : (
          <SectionList
            sections={sections}
            keyExtractor={(item) => String(item.id)}
            stickySectionHeadersEnabled={false}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={{ paddingBottom: spacing.xl, flexGrow: 1 }}
            ListEmptyComponent={
              tab === 'active' ? (
                <EmptyState
                  icon="flame-outline"
                  title="No active duels"
                  subtitle="Challenge a friend to a head-to-head draft to get started."
                  action={<Button title="New Challenge" icon="add" onPress={() => navigation.navigate('CreateChallenge')} />}
                />
              ) : (
                <EmptyState icon="time-outline" title="No past duels yet" subtitle="Finished duels will show up here." />
              )
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
                      <Text style={styles.emoji}>{item.group ? '👥' : SPORT_EMOJI[item.sport] || '🎯'}</Text>
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.vs}>{rowTitle(item)}</Text>
                      <Text style={styles.meta}>{rowMeta(item)}</Text>
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

function SegTab({ label, count, on, onPress, styles, colors }) {
  return (
    <Pressable onPress={onPress} style={[styles.segTab, on && styles.segTabOn]}>
      <Text style={[styles.segLabel, { color: on ? colors.onAccent : colors.muted }]}>
        {label}
        {count > 0 ? `  ${count}` : ''}
      </Text>
    </Pressable>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    body: { flex: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.md },
    segment: { flexDirection: 'row', gap: spacing.xs, backgroundColor: colors.card, borderRadius: radius.md, padding: spacing.xs, marginTop: spacing.md, borderWidth: 1, borderColor: colors.borderSubtle },
    segTab: { flex: 1, alignItems: 'center', paddingVertical: 10, borderRadius: radius.sm },
    segTabOn: { backgroundColor: colors.accent },
    segLabel: { fontSize: font.body, fontWeight: '700' },
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
