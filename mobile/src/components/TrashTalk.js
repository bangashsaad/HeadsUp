import { KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { useTheme, useThemedStyles, spacing, radius, font, fonts, withAlpha } from '../theme';
import { CondTitle, Kicker } from './ui';

// The rivalry's text thread — your jabs right-aligned in lime, theirs left in
// purple, capped input, send pill. One component so the live room and the
// post-game receipt argue in the same voice.
export default function TrashTalk({ chat, draft, setDraft, onSend, sending, title = 'TRASH TALK' }) {
  const { user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const myId = user?.id;

  return (
    <View style={styles.talkCard}>
      <View style={styles.talkHead}>
        <CondTitle size={15} color={colors.text} style={{ letterSpacing: 1 }}>
          {title}
        </CondTitle>
        <Kicker size={9} tracking={1.5}>
          Only the duel can see this
        </Kicker>
      </View>

      {chat.length === 0 ? (
        <Text style={styles.talkEmpty}>Say something. Scoreboard talk is free.</Text>
      ) : (
        <View style={styles.talkThread}>
          {chat.slice(-30).map((m) => {
            const mine = String(m.user_id) === String(myId);
            return (
              <View key={m.id} style={{ alignItems: mine ? 'flex-end' : 'flex-start' }}>
                <Text style={[styles.talkWho, { color: mine ? colors.accent : colors.purpleText }]}>
                  {mine ? 'YOU' : m.username.toUpperCase()}
                </Text>
                <View
                  style={[
                    styles.talkBubble,
                    mine
                      ? { backgroundColor: withAlpha(colors.accent, 0.1), borderColor: withAlpha(colors.accent, 0.35) }
                      : { backgroundColor: withAlpha(colors.purple, 0.12), borderColor: withAlpha(colors.purple, 0.4) },
                  ]}
                >
                  <Text style={styles.talkText}>{m.body}</Text>
                </View>
              </View>
            );
          })}
        </View>
      )}

      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={styles.talkRow}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            placeholder="Talk your talk…"
            placeholderTextColor={colors.placeholder}
            maxLength={280}
            style={styles.talkInput}
            onSubmitEditing={onSend}
            returnKeyType="send"
          />
          <Pressable
            onPress={onSend}
            disabled={sending || !draft.trim()}
            style={({ pressed }) => [
              styles.talkSend,
              (sending || !draft.trim()) && { opacity: 0.35 },
              pressed && { opacity: 0.7 },
            ]}
          >
            <Text style={{ color: colors.onAccent, fontFamily: fonts.bodyBlack, fontSize: 15 }}>➤</Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </View>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    talkCard: { marginTop: spacing.xl, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.card },
    talkHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md, paddingTop: spacing.md },
    talkEmpty: { color: colors.placeholder, fontSize: font.small, padding: spacing.md, textAlign: 'center' },
    talkThread: { padding: spacing.md, gap: 9 },
    talkWho: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1, marginBottom: 2 },
    talkBubble: { borderWidth: 1, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8, maxWidth: '80%' },
    talkText: { color: colors.text, fontSize: 13, lineHeight: 19 },
    talkRow: { flexDirection: 'row', gap: 8, padding: spacing.md, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.borderSubtle },
    talkInput: { flex: 1, backgroundColor: colors.bgElevated, borderWidth: 1, borderColor: colors.border, borderRadius: 999, paddingHorizontal: 15, paddingVertical: 10, color: colors.text, fontSize: 13, fontFamily: fonts.body },
    talkSend: { width: 40, height: 40, borderRadius: 999, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center' },
  });
