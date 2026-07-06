import { View, Text } from 'react-native';
import { avatarColor, fonts } from '../../theme';

// Initials tile with a stable per-name tint. Rounded square ("squircle"), per
// the Reimagined language. (8-digit hex appends alpha.)
export default function Avatar({ name = '', size = 44, round = false, style }) {
  const initials =
    name
      .trim()
      .split(/\s+/)
      .map((w) => w[0])
      .slice(0, 2)
      .join('')
      .toUpperCase() || '?';
  const tint = avatarColor(name);

  return (
    <View
      style={[
        {
          width: size,
          height: size,
          borderRadius: round ? size / 2 : Math.round(size * 0.32),
          backgroundColor: tint + '22',
          borderWidth: 1.5,
          borderColor: tint + '66',
          alignItems: 'center',
          justifyContent: 'center',
        },
        style,
      ]}
    >
      <Text style={{ color: tint, fontFamily: fonts.bodyExtra, fontSize: size * 0.38 }}>{initials}</Text>
    </View>
  );
}
