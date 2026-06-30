import { createNativeStackNavigator } from '@react-navigation/native-stack';
import SportsHomeScreen from '../screens/SportsHomeScreen';
import PlayersScreen from '../screens/PlayersScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

export default function SportsStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="SportsHome" component={SportsHomeScreen} options={{ title: 'Sports' }} />
      <Stack.Screen name="Players" component={PlayersScreen} options={({ route }) => ({ title: route.params.label })} />
    </Stack.Navigator>
  );
}
