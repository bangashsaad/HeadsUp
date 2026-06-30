import { View, Text } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, spacing, font } from '../../theme';

// Friendly centered placeholder: an icon coin, a title, a subtitle, and an
// optional action node (e.g. a Button).
export default function EmptyState({ icon = 'sparkles-outline', title, subtitle, action, style }) {
  const { colors } = useTheme();
  return (
    <View style={[{ alignItems: 'center', justifyContent: 'center', paddingVertical: spacing.xxl, paddingHorizontal: spacing.xl }, style]}>
      <View
        style={{
          width: 64,
          height: 64,
          borderRadius: 32,
          backgroundColor: colors.card,
          alignItems: 'center',
          justifyContent: 'center',
          marginBottom: spacing.lg,
          borderWidth: 1,
          borderColor: colors.borderSubtle,
        }}
      >
        <Ionicons name={icon} size={30} color={colors.muted} />
      </View>
      {title ? <Text style={{ color: colors.text, fontSize: font.subtitle, fontWeight: '700', textAlign: 'center' }}>{title}</Text> : null}
      {subtitle ? (
        <Text style={{ color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: 6, lineHeight: 21 }}>{subtitle}</Text>
      ) : null}
      {action ? <View style={{ marginTop: spacing.lg, alignSelf: 'stretch' }}>{action}</View> : null}
    </View>
  );
}
