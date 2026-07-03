import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import LineupSlots from './LineupSlots';
import { Avatar } from './ui';
import { useTheme, useThemedStyles, spacing, radius, font } from '../theme';

// Bottom-sheet roster viewer: the fitted half-width draft columns truncate,
// so tapping a column opens one side's full lineup with team + auto detail.
// Also the roster view for 3+-player drafts later (avatar tab → this sheet).
export default function RosterSheet({ visible, onClose, title, name, slots, picks }) {
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.wrap}>
        <Pressable style={styles.backdrop} onPress={onClose} />
        <View style={styles.sheet}>
          <View style={styles.handle} />
          <View style={styles.head}>
            <Avatar name={name || title} size={30} />
            <Text style={styles.title} numberOfLines={1}>
              {title}
            </Text>
            <Pressable onPress={onClose} hitSlop={10}>
              <Ionicons name="close" size={22} color={colors.muted} />
            </Pressable>
          </View>
          <ScrollView bounces={false}>
            <LineupSlots slots={slots} picks={picks} />
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    wrap: { flex: 1, justifyContent: 'flex-end' },
    backdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.55)' },
    sheet: {
      backgroundColor: colors.bg,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
      borderWidth: 1,
      borderColor: colors.border,
      padding: spacing.lg,
      paddingBottom: spacing.xxl,
      maxHeight: '75%',
    },
    handle: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: colors.border, marginBottom: spacing.md },
    head: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, marginBottom: spacing.md },
    title: { color: colors.text, fontSize: font.subtitle, fontWeight: '800', flex: 1 },
  });
