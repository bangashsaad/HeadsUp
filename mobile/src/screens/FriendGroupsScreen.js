import { useCallback, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import {
  listFriends,
  listFriendGroups,
  createFriendGroup,
  renameFriendGroup,
  deleteFriendGroup,
  setFriendGroupMembers,
} from '../api/social';
import { selection, impact, ImpactStyle } from '../haptics';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, Button, EmptyState, SkeletonList } from '../components/ui';

const NAME_MAX = 20;

// Private buckets of friends ("CREW", "WORK") that become the recipient tabs
// on the challenge screen. Nobody sees the group they're in.
export default function FriendGroupsScreen() {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  const [friends, setFriends] = useState([]);
  const [groups, setGroups] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null); // group being edited
  const [naming, setNaming] = useState(false);
  const [draftName, setDraftName] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [f, g] = await Promise.all([listFriends(token), listFriendGroups(token)]);
      setFriends(f.friends || []);
      setGroups(g.groups || []);
      setError(null);
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

  async function submitName() {
    const name = draftName.trim();
    if (!name) return;
    setBusy(true);
    try {
      if (naming === 'new') await createFriendGroup(token, name);
      else await renameFriendGroup(token, naming.id, name);
      setNaming(false);
      setDraftName('');
      await load();
    } catch (e) {
      Alert.alert("Couldn't save", e.message);
    } finally {
      setBusy(false);
    }
  }

  function confirmDelete(group) {
    Alert.alert(`Delete ${group.name}?`, 'The group goes away. Your friendships are untouched.', [
      { text: 'Keep', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteFriendGroup(token, group.id);
            await load();
          } catch (e) {
            Alert.alert("Couldn't delete", e.message);
          }
        },
      },
    ]);
  }

  async function toggleMember(group, friendId) {
    const current = group.member_ids || [];
    const next = current.includes(friendId) ? current.filter((x) => x !== friendId) : [...current, friendId];
    impact(ImpactStyle.Light);
    // Optimistic — the server replaces membership wholesale.
    setEditing({ ...group, member_ids: next });
    setGroups((gs) => gs.map((g) => (g.id === group.id ? { ...g, member_ids: next } : g)));
    try {
      await setFriendGroupMembers(token, group.id, next);
    } catch (e) {
      Alert.alert("Couldn't update", e.message);
      load();
    }
  }

  if (loading) {
    return (
      <Screen>
        <SkeletonList count={5} />
      </Screen>
    );
  }

  return (
    <Screen scroll>
      <Text style={styles.intro}>
        Groups are private shortcuts for challenging people — nobody knows which group they're in. A friend can be in
        several.
      </Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      {friends.length === 0 ? (
        <EmptyState icon="people-outline" title="No friends yet" subtitle="Add friends first — then you can group them." />
      ) : (
        <>
          {groups.map((g) => (
            <View key={g.id} style={styles.card}>
              <Pressable
                onPress={() => {
                  selection();
                  setEditing(editing?.id === g.id ? null : g);
                }}
                style={styles.cardHead}
              >
                <Text style={styles.groupName}>{g.name.toUpperCase()}</Text>
                <Text style={styles.groupCount}>{(g.member_ids || []).length}</Text>
                <Ionicons
                  name={editing?.id === g.id ? 'chevron-up' : 'chevron-down'}
                  size={17}
                  color={colors.placeholder}
                />
              </Pressable>

              {editing?.id === g.id ? (
                <View>
                  {friends.map((f, i) => {
                    const inGroup = (editing.member_ids || []).includes(f.id);
                    return (
                      <Pressable
                        key={f.id}
                        onPress={() => toggleMember(editing, f.id)}
                        style={({ pressed }) => [
                          styles.person,
                          i < friends.length - 1 && styles.divider,
                          pressed && { backgroundColor: colors.cardElevated },
                        ]}
                      >
                        <Avatar name={f.username} size={34} />
                        <Text style={styles.personName} numberOfLines={1}>
                          {f.username}
                        </Text>
                        <Ionicons
                          name={inGroup ? 'checkmark-circle' : 'ellipse-outline'}
                          size={21}
                          color={inGroup ? colors.accent : colors.placeholder}
                        />
                      </Pressable>
                    );
                  })}
                  <View style={styles.cardActions}>
                    <Pressable
                      onPress={() => {
                        setNaming(g);
                        setDraftName(g.name);
                      }}
                      hitSlop={8}
                    >
                      <Text style={styles.linkBtn}>Rename</Text>
                    </Pressable>
                    <Pressable onPress={() => confirmDelete(g)} hitSlop={8}>
                      <Text style={[styles.linkBtn, { color: colors.danger }]}>Delete</Text>
                    </Pressable>
                  </View>
                </View>
              ) : null}
            </View>
          ))}

          <Button
            title="New group"
            icon="add"
            variant="outline"
            onPress={() => {
              setNaming('new');
              setDraftName('');
            }}
            style={{ marginTop: spacing.md }}
          />
        </>
      )}

      <Modal visible={!!naming} transparent animationType="fade" onRequestClose={() => setNaming(false)}>
        <Pressable style={styles.backdrop} onPress={() => setNaming(false)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <Text style={styles.sheetTitle}>{naming === 'new' ? 'NEW GROUP' : 'RENAME GROUP'}</Text>
            <TextInput
              value={draftName}
              onChangeText={(t) => setDraftName(t.slice(0, NAME_MAX))}
              placeholder="Crew"
              placeholderTextColor={colors.placeholder}
              style={styles.input}
              autoFocus
              autoCapitalize="words"
              onSubmitEditing={submitName}
            />
            <Text style={styles.hint}>
              {draftName.trim().length}/{NAME_MAX}
            </Text>
            <Button title="Save" onPress={submitName} loading={busy} disabled={!draftName.trim()} style={{ marginTop: spacing.sm }} />
          </Pressable>
        </Pressable>
      </Modal>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    intro: { color: colors.muted, fontSize: 13, lineHeight: 19, marginBottom: spacing.lg, fontFamily: fonts.body },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.sm },
    card: {
      backgroundColor: colors.card,
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      overflow: 'hidden',
      marginBottom: spacing.sm,
    },
    cardHead: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 14, paddingVertical: 14 },
    groupName: { flex: 1, color: colors.text, fontSize: 14, fontFamily: fonts.heroUpright, letterSpacing: 1.5 },
    groupCount: { color: colors.accent, fontSize: 13, fontFamily: fonts.bodyBlack },
    divider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.borderSubtle },
    person: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 14, paddingVertical: 9, minHeight: 52 },
    personName: { flex: 1, color: colors.text, fontSize: 14, fontFamily: fonts.bodyBold },
    cardActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.lg, padding: 14 },
    linkBtn: { color: colors.accent, fontSize: 13, fontFamily: fonts.bodyBold },

    backdrop: { flex: 1, backgroundColor: withAlpha('#000000', 0.65), justifyContent: 'center', padding: spacing.lg },
    sheet: { backgroundColor: colors.card, borderRadius: 18, borderWidth: 1, borderColor: colors.border, padding: spacing.lg },
    sheetTitle: { color: colors.text, fontSize: 15, fontFamily: fonts.heroUpright, letterSpacing: 1.5, marginBottom: spacing.md },
    input: {
      color: colors.text,
      fontSize: 18,
      fontFamily: fonts.bodyBold,
      paddingVertical: 12,
      paddingHorizontal: 14,
      borderRadius: 13,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.cardElevated,
    },
    hint: { color: colors.placeholder, fontSize: 11, textAlign: 'right', marginTop: 5, fontFamily: fonts.body },
  });
