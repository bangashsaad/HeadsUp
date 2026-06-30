import { useState } from 'react';
import { View, Text, TextInput, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, radius, spacing, font } from '../../theme';

// Labeled text input with optional password show/hide, a valid ✓, and an error.
export default function Field({
  label,
  value,
  onChangeText,
  placeholder,
  secure = false,
  error,
  valid,
  keyboardType,
  autoCapitalize = 'none',
  autoFocus = false,
  style,
}) {
  const { colors } = useTheme();
  const [hidden, setHidden] = useState(secure);

  return (
    <View style={[{ marginBottom: spacing.md }, style]}>
      {label ? <Text style={{ color: colors.muted, fontSize: font.small, fontWeight: '700', marginBottom: 6 }}>{label}</Text> : null}
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          backgroundColor: colors.card,
          borderRadius: radius.md,
          borderWidth: 1,
          borderColor: error ? colors.dangerBorder : colors.border,
          paddingHorizontal: spacing.md,
        }}
      >
        <TextInput
          style={{ flex: 1, color: colors.text, fontSize: font.bodyLg, paddingVertical: 14 }}
          placeholder={placeholder}
          placeholderTextColor={colors.placeholder}
          value={value}
          onChangeText={onChangeText}
          secureTextEntry={hidden}
          keyboardType={keyboardType}
          autoCapitalize={autoCapitalize}
          autoCorrect={false}
          autoFocus={autoFocus}
        />
        {valid ? <Ionicons name="checkmark-circle" size={18} color={colors.accent} style={{ marginLeft: 6 }} /> : null}
        {secure ? (
          <Pressable onPress={() => setHidden((h) => !h)} hitSlop={8} style={{ marginLeft: 6 }}>
            <Ionicons name={hidden ? 'eye-outline' : 'eye-off-outline'} size={20} color={colors.placeholder} />
          </Pressable>
        ) : null}
      </View>
      {error ? <Text style={{ color: colors.danger, fontSize: font.small, marginTop: 6 }}>{error}</Text> : null}
    </View>
  );
}
