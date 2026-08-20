import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, RefreshControl, ScrollView, Share, StyleSheet, Text, TextInput, View, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import {
  listFriends,
  listRequests,
  listFriendGroups,
  searchUsers,
  sendFriendRequest,
  acceptRequest,
  deleteRequest,
} from '../api/social';
import { getMyStats } from '../api/me';
import { setFriendReqs } from '../state/attention';
import { useTheme, useThemedStyles, avatarColor, spacing, fonts, withAlpha } from '../theme';
import { Screen, SkeletonList, EmptyState, Button } from '../components/ui';

// The FRIENDS tab, from Saad's Reimagined drop: requests inline at the top,
// search that surfaces strangers, group pills as filters, and every friend row
// carrying the series record vs you plus a one-tap ⚔ DUEL.
export default function FriendsScreen({ navigation, route }) {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [groups, setGroups] = useState([]);
  const [h2h, setH2h] = useState({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState(null);

  const [q, setQ] = useState('');

  // A /u/:username link lands here with the name — run the search on arrival.
  useEffect(() => {
    const seed = route?.params?.q;
    if (seed) setQ(String(seed));
  }, [route?.params?.q]);
  const [results, setResults] = useState([]);
  const [sentIds, setSentIds] = useState(new Set());
  const [grp, setGrp] = useState('all');
  const debounce = useRef(null);

  const load = useCallback(async () => {
    try {
      const [f, r, g, s] = await Promise.all([
        listFriends(token),
        listRequests(token),
        listFriendGroups(token),
        getMyStats(token).catch(() => ({ head_to_head: [] })),
      ]);
      setFriends(f.friends);
      setRequests(r.requests);
      setGroups(g.groups || []);
      setH2h(Object.fromEntries((s.head_to_head || []).map((row) => [row.opponent.id, row])));
      setFriendReqs(r.requests.length);
      setLoadError(null);
    } catch (e) {
      // A dead network must not render as "nobody in your corner".
      setLoadError(e.message || 'Could not load your crew.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  // Debounced username search; two characters minimum, same as the server.
  useEffect(() => {
    if (debounce.current) clearTimeout(debounce.current);
    const trimmed = q.trim();
    if (trimmed.length < 2) {
      setResults([]);
      return;
    }
    debounce.current = setTimeout(() => {
      searchUsers(token, trimmed)
        .then((res) => setResults(res.users || []))
        .catch(() => {});
    }, 300);
    return () => clearTimeout(debounce.current);
  }, [q, token]);

  async function accept(friendshipId) {
    try {
      await acceptRequest(token, friendshipId);
    } catch (e) {
      Alert.alert("Couldn't accept that", e.message);
    }
    load();
  }

  async function decline(friendshipId) {
    try {
      await deleteRequest(token, friendshipId);
    } catch (e) {
      Alert.alert("Couldn't decline that", e.message);
    }
    load();
  }

  async function sendRequest(userId) {
    try {
      await sendFriendRequest(token, userId);
      setSentIds((prev) => new Set(prev).add(userId));
    } catch (e) {
      Alert.alert("Request didn't send", e.message);
    }
  }

  function openRivalry(f) {
    navigation.navigate('Rivalry', { id: f.id, username: f.username });
  }

  function challenge(id) {
    navigation.navigate('DuelsTab', { screen: 'CreateChallenge', params: { preselect: id }, initial: false });
  }

  function invite() {
    Share.share({ message: `Duel me on HeadsUp Fantasy — I'm ${user?.username}. First duel's on the house.` }).catch(() => {});
  }

  const frag = q.trim().toLowerCase();
  const inGroup = (f) => {
    if (grp === 'all') return true;
    const g = groups.find((x) => x.id === grp);
    return !!g && g.member_ids.includes(f.id);
  };
  const crew = friends.filter((f) => (!frag || f.username.toLowerCase().includes(frag)) && inGroup(f));
  const strangers = results.filter((r) => r.relationship !== 'friends');
  const noMatch = frag.length >= 2 && crew.length === 0 && strangers.length === 0;

  function recFor(f) {
    const r = h2h[f.id];
    if (!r || r.played === 0) return { text: '0–0', color: colors.placeholder };
    if (r.wins > r.losses) return { text: `${r.wins}–${r.losses}`, color: colors.accent };
    if (r.wins < r.losses) return { text: `${r.wins}–${r.losses}`, color: colors.danger };
    return { text: `${r.wins}–${r.losses}`, color: colors.muted };
  }

  function subFor(f) {
    const names = groups.filter((g) => g.member_ids.includes(f.id)).map((g) => g.name);
    if (names.length) return names.join(' · ');
    const r = h2h[f.id];
    return r && r.played > 0 ? 'No groups yet' : 'New · never played';
  }

  if (loading) {
    return (
      <Screen edges={['top']}>
        <SkeletonList count={7} />
      </Screen>
    );
  }

  if (loadError && friends.length === 0 && requests.length === 0) {
    return (
      <Screen edges={['top']}>
        <EmptyState
          icon="cloud-offline-outline"
          title="Couldn't reach the server"
          subtitle={loadError}
          action={<Button title="Try again" icon="refresh" onPress={() => { setLoading(true); load(); }} />}
        />
      </Screen>
    );
  }

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: spacing.xxl }}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor={colors.accent} />
        }
      >
        <LinearGradient
          colors={[withAlpha(colors.purple, 0.18), 'transparent']}
          start={{ x: 0.2, y: 0 }}
          end={{ x: 0.6, y: 1 }}
          style={styles.headerZone}
        >
          <View style={styles.titleRow}>
            <Text style={styles.title}>FRIENDS</Text>
            <Text style={styles.counter}>{friends.length} IN YOUR CORNER</Text>
          </View>
          <View style={styles.searchPill}>
            <Ionicons name="search" size={14} color={colors.placeholder} />
            <TextInput
              style={styles.searchInput}
              value={q}
              onChangeText={setQ}
              placeholder="Search usernames…"
              placeholderTextColor={colors.placeholder}
              autoCapitalize="none"
              autoCorrect={false}
            />
            {q !== '' && (
              <Pressable onPress={() => setQ('')} hitSlop={8}>
                <Ionicons name="close-circle" size={16} color={colors.placeholder} />
              </Pressable>
            )}
          </View>
        </LinearGradient>

        {requests.length > 0 && (
          <View style={styles.section}>
            <View style={styles.reqHead}>
              <Text style={styles.reqLabel}>REQUESTS</Text>
              <View style={styles.reqCount}>
                <Text style={styles.reqCountText}>{requests.length}</Text>
              </View>
            </View>
            {requests.map((r) => {
              const tint = avatarColor(r.user.username);
              return (
                <View key={r.id} style={styles.reqCard}>
                  <View style={[styles.avatar, { width: 32, height: 32, borderRadius: 10, backgroundColor: tint + '22', borderColor: tint + '55' }]}>
                    <Text style={[styles.avatarText, { color: tint, fontSize: 12 }]}>{r.user.username[0].toUpperCase()}</Text>
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.rowName} numberOfLines={1}>{r.user.username}</Text>
                    <Text style={styles.wantsIn}>WANTS IN</Text>
                  </View>
                  <Pressable onPress={() => accept(r.id)} style={({ pressed }) => [styles.acceptPill, pressed && styles.pressed]}>
                    <Text style={styles.acceptText}>ACCEPT</Text>
                  </Pressable>
                  <Pressable onPress={() => decline(r.id)} style={({ pressed }) => [styles.declineCircle, pressed && styles.pressed]}>
                    <Text style={styles.declineX}>✕</Text>
                  </Pressable>
                </View>
              );
            })}
          </View>
        )}

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0 }} contentContainerStyle={styles.tabsRow}>
          {groups.length > 0 &&
            [{ id: 'all', name: 'ALL' }, ...groups].map((g) => {
              const on = grp === g.id;
              const n = g.id === 'all' ? friends.length : g.member_ids.length;
              return (
                <Pressable
                  key={g.id}
                  onPress={() => setGrp(g.id)}
                  style={[styles.tabPill, on && { borderColor: colors.purple, backgroundColor: withAlpha(colors.purple, 0.15) }]}
                >
                  <Text style={[styles.tabText, on && { color: colors.purpleText }]}>
                    {g.name} <Text style={{ opacity: 0.6 }}>{n}</Text>
                  </Text>
                </Pressable>
              );
            })}
          <Pressable
            onPress={() => navigation.navigate('FriendGroups')}
            style={[styles.tabPill, { borderStyle: 'dashed', borderColor: withAlpha(colors.purple, 0.5) }]}
          >
            <Text style={[styles.tabText, { color: colors.purpleText }]}>
              {groups.length > 0 ? '⚙ GROUPS' : '＋ NEW GROUP'}
            </Text>
          </Pressable>
        </ScrollView>

        <View style={styles.section}>
          {crew.map((f) => {
            const tint = avatarColor(f.username);
            const rec = recFor(f);
            return (
              <Pressable key={f.id} onPress={() => openRivalry(f)} style={({ pressed }) => [styles.row, pressed && styles.pressed]}>
                <View style={{ position: 'relative' }}>
                  <View style={[styles.avatar, { backgroundColor: tint + '22', borderColor: tint + '55' }]}>
                    <Text style={[styles.avatarText, { color: tint }]}>{f.username[0].toUpperCase()}</Text>
                  </View>
                  {f.online && <View style={styles.onlineDot} />}
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={styles.rowName} numberOfLines={1}>{f.username}</Text>
                  <Text style={styles.rowSub} numberOfLines={1}>{subFor(f)}</Text>
                </View>
                <Text style={[styles.rec, { color: rec.color }]}>{rec.text}</Text>
                <Pressable
                  onPress={(e) => { e.stopPropagation && e.stopPropagation(); challenge(f.id); }}
                  style={({ pressed }) => [styles.duelPill, pressed && styles.pressed]}
                >
                  <Text style={styles.duelText}>⚔ DUEL</Text>
                </Pressable>
                <Text style={styles.chevron}>›</Text>
              </Pressable>
            );
          })}

          {friends.length === 0 && frag.length < 2 && (
            <EmptyState
              icon="people-outline"
              title="Nobody in your corner yet"
              subtitle="Search a username above, or send an invite — first duel's on the house."
              action={<Button title="Invite a friend" icon="share-outline" onPress={invite} />}
            />
          )}
        </View>

        {strangers.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.strangerLabel}>NOT IN YOUR CORNER YET</Text>
            {strangers.map((s) => {
              const sent = s.relationship === 'request_sent' || sentIds.has(s.id);
              const askedFirst = s.relationship === 'request_received';
              return (
                <View key={s.id} style={styles.strangerRow}>
                  <View style={[styles.avatar, { backgroundColor: colors.borderSubtle, borderColor: colors.border }]}>
                    <Text style={[styles.avatarText, { color: colors.muted }]}>{s.username[0].toUpperCase()}</Text>
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.rowName} numberOfLines={1}>{s.username}</Text>
                    <Text style={styles.rowSub} numberOfLines={1}>{s.meta || 'new here'}</Text>
                  </View>
                  {askedFirst ? (
                    <Pressable onPress={() => accept(s.friendship_id)} style={({ pressed }) => [styles.requestPill, pressed && styles.pressed]}>
                      <Text style={styles.requestText}>THEY ASKED — ACCEPT</Text>
                    </Pressable>
                  ) : sent ? (
                    <View style={styles.sentPill}>
                      <Text style={styles.sentText}>SENT ✓</Text>
                    </View>
                  ) : (
                    <Pressable onPress={() => sendRequest(s.id)} style={({ pressed }) => [styles.requestPill, pressed && styles.pressed]}>
                      <Text style={styles.requestText}>+ REQUEST</Text>
                    </Pressable>
                  )}
                </View>
              );
            })}
          </View>
        )}

        {noMatch && (
          <Pressable onPress={invite} style={styles.noMatch}>
            <Text style={styles.noMatchTitle}>NOBODY BY THAT NAME</Text>
            <Text style={styles.noMatchSub}>Send them an invite link — first duel's on the house.</Text>
          </Pressable>
        )}
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.md },
    titleRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between' },
    title: { fontFamily: fonts.display, fontSize: 24, letterSpacing: -0.5, color: colors.text },
    counter: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1, color: colors.placeholder },
    searchPill: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingHorizontal: 14,
      paddingVertical: 10,
      marginTop: 12,
    },
    searchInput: { flex: 1, minWidth: 0, color: colors.text, fontFamily: fonts.body, fontSize: 13, padding: 0 },
    section: { paddingHorizontal: spacing.lg, paddingTop: spacing.md, gap: 7 },
    reqHead: { flexDirection: 'row', alignItems: 'center', gap: 7 },
    reqLabel: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.cyan },
    reqCount: { backgroundColor: colors.cyan, borderRadius: 999, paddingHorizontal: 7, paddingVertical: 1 },
    reqCountText: { color: '#0A0B10', fontSize: 9, fontFamily: fonts.bodyBlack },
    reqCard: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: withAlpha(colors.cyan, 0.35),
      backgroundColor: withAlpha(colors.cyan, 0.05),
      paddingHorizontal: 12,
      paddingVertical: 10,
    },
    avatar: {
      width: 34,
      height: 34,
      borderRadius: 11,
      borderWidth: 1,
      alignItems: 'center',
      justifyContent: 'center',
      flexShrink: 0,
    },
    avatarText: { fontFamily: fonts.bodyExtra, fontSize: 13 },
    onlineDot: {
      position: 'absolute',
      right: -2,
      bottom: -2,
      width: 9,
      height: 9,
      borderRadius: 5,
      backgroundColor: colors.green,
      borderWidth: 2,
      borderColor: colors.bg,
    },
    rowName: { fontSize: 13, fontFamily: fonts.bodyBold, color: colors.text },
    rowSub: { fontSize: 10, color: colors.muted, marginTop: 1 },
    wantsIn: { fontSize: 9.5, fontFamily: fonts.bodyExtra, color: colors.cyan, marginTop: 1 },
    acceptPill: { backgroundColor: colors.accent, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 7 },
    acceptText: { color: colors.onAccent, fontFamily: fonts.hero, fontSize: 13 },
    declineCircle: {
      width: 30,
      height: 30,
      borderRadius: 15,
      borderWidth: 1,
      borderColor: colors.border,
      alignItems: 'center',
      justifyContent: 'center',
    },
    declineX: { color: colors.muted, fontSize: 13, fontFamily: fonts.bodyExtra },
    tabsRow: { gap: 6, paddingHorizontal: spacing.lg, paddingTop: spacing.lg },
    tabPill: {
      borderRadius: 999,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      paddingHorizontal: 13,
      paddingVertical: 7,
    },
    tabText: { fontFamily: fonts.heroUpright, fontSize: 12.5, letterSpacing: 1, color: colors.muted, lineHeight: 16 },
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
      paddingHorizontal: 12,
      paddingVertical: 10,
    },
    rec: { fontFamily: fonts.hero, fontSize: 16, flexShrink: 0 },
    duelPill: {
      borderWidth: 1,
      borderColor: withAlpha(colors.accent, 0.6),
      borderRadius: 999,
      paddingHorizontal: 12,
      paddingVertical: 6,
      flexShrink: 0,
    },
    duelText: { color: colors.accent, fontFamily: fonts.hero, fontSize: 12.5 },
    chevron: { color: colors.textFaint, fontSize: 14, fontFamily: fonts.bodyBold, flexShrink: 0 },
    strangerLabel: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.placeholder },
    strangerRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      borderRadius: 12,
      borderWidth: 1,
      borderStyle: 'dashed',
      borderColor: colors.textFaint,
      backgroundColor: colors.bgElevated,
      paddingHorizontal: 12,
      paddingVertical: 10,
    },
    requestPill: { backgroundColor: colors.accent, borderRadius: 999, paddingHorizontal: 14, paddingVertical: 7, flexShrink: 0 },
    requestText: { color: colors.onAccent, fontFamily: fonts.hero, fontSize: 12.5 },
    sentPill: {
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingHorizontal: 14,
      paddingVertical: 7,
      flexShrink: 0,
    },
    sentText: { color: colors.placeholder, fontFamily: fonts.hero, fontSize: 12.5 },
    noMatch: { paddingVertical: 30, paddingHorizontal: spacing.lg, alignItems: 'center', gap: 6 },
    noMatchTitle: { fontFamily: fonts.hero, fontSize: 19, color: colors.muted, letterSpacing: 1 },
    noMatchSub: { fontSize: 11, color: colors.placeholder, fontFamily: fonts.bodySemi },
    pressed: { opacity: 0.85, transform: [{ scale: 0.985 }] },
  });
