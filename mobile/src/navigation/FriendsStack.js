import { createNativeStackNavigator } from '@react-navigation/native-stack';
import FriendsScreen from '../screens/FriendsScreen';
import RivalryScreen from '../screens/RivalryScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

// The FRIENDS tab: the crew (requests inline, search inline, group filters)
// with each rivalry one tap deep.
export default function FriendsStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="FriendsHome" component={FriendsScreen} options={{ headerShown: false }} />
      <Stack.Screen name="Rivalry" component={RivalryScreen} options={{ title: 'RIVALRY' }} />
    </Stack.Navigator>
  );
}
