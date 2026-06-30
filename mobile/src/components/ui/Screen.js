import { View, ScrollView, KeyboardAvoidingView, Platform, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme, spacing } from '../../theme';

// Page wrapper: themed bg, keyboard avoidance, and an optional scroll view with
// pull-to-refresh. No safe-area insets by default (the header owns the top, the
// tab bar owns the bottom).
export default function Screen({
  children,
  scroll = false,
  padded = true,
  style,
  contentStyle,
  edges = [],
  refreshing,
  onRefresh,
}) {
  const { colors } = useTheme();
  const padStyle = padded ? { padding: spacing.lg } : null;

  const refreshControl =
    onRefresh != null ? (
      <RefreshControl refreshing={!!refreshing} onRefresh={onRefresh} tintColor={colors.muted} />
    ) : undefined;

  const inner = scroll ? (
    <ScrollView
      contentContainerStyle={[padStyle, contentStyle]}
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
      refreshControl={refreshControl}
    >
      {children}
    </ScrollView>
  ) : (
    <View style={[{ flex: 1 }, padStyle, contentStyle]}>{children}</View>
  );

  return (
    <SafeAreaView edges={edges} style={[{ flex: 1, backgroundColor: colors.bg }, style]}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        {inner}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
