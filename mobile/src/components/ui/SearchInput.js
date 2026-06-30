import { View, TextInput, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, radius, spacing, font } from '../../theme';

// Text field with a leading search icon and a clear (×) button.
export default function SearchInput({ value, onChangeText, placeholder = 'Search', style, autoFocus = false }) {
  return (
    <View
      style={[
        {
          flexDirection: 'row',
          alignItems: 'center',
          backgroundColor: colors.card,
          borderRadius: radius.md,
          borderWidth: 1,
          borderColor: colors.border,
          paddingHorizontal: spacing.md,
        },
        style,
      ]}
    >
      <Ionicons name="search" size={18} color={colors.placeholder} />
      <TextInput
        style={{ flex: 1, color: colors.text, fontSize: font.bodyLg, paddingVertical: 12, paddingHorizontal: spacing.sm }}
        placeholder={placeholder}
        placeholderTextColor={colors.placeholder}
        autoCapitalize="none"
        autoCorrect={false}
        value={value}
        onChangeText={onChangeText}
        autoFocus={autoFocus}
        returnKeyType="search"
      />
      {value ? (
        <Pressable onPress={() => onChangeText('')} hitSlop={8}>
          <Ionicons name="close-circle" size={18} color={colors.placeholder} />
        </Pressable>
      ) : null}
    </View>
  );
}
