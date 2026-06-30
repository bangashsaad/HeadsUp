import { createNativeStackNavigator } from '@react-navigation/native-stack';
import FriendsScreen from '../screens/FriendsScreen';
import SearchScreen from '../screens/SearchScreen';
import RequestsScreen from '../screens/RequestsScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

export default function FriendsStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="Friends" component={FriendsScreen} />
      <Stack.Screen name="Search" component={SearchScreen} options={{ title: 'Add Friends' }} />
      <Stack.Screen name="Requests" component={RequestsScreen} options={{ title: 'Friend Requests' }} />
    </Stack.Navigator>
  );
}
