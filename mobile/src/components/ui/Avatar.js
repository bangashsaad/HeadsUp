import { View, Text } from 'react-native';
import { avatarColor } from '../../theme';

// Initials avatar with a stable per-name tint. (8-digit hex appends alpha.)
export default function Avatar({ name = '', size = 44, style }) {
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
          borderRadius: size / 2,
          backgroundColor: tint + '22',
          borderWidth: 1.5,
          borderColor: tint + '55',
          alignItems: 'center',
          justifyContent: 'center',
        },
        style,
      ]}
    >
      <Text style={{ color: tint, fontWeight: '800', fontSize: size * 0.4 }}>{initials}</Text>
    </View>
  );
}
