import { createNativeStackNavigator } from '@react-navigation/native-stack';
import GamesScreen from '../screens/GamesScreen';
import GameDetailScreen from '../screens/GameDetailScreen';
import PlayerProfileScreen from '../screens/PlayerProfileScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

export default function GamesStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="Games" component={GamesScreen} options={{ title: 'Games' }} />
      <Stack.Screen name="GameDetail" component={GameDetailScreen} options={{ title: 'Matchup' }} />
      <Stack.Screen
        name="PlayerProfile"
        component={PlayerProfileScreen}
        options={({ route }) => ({ title: route.params?.name || 'Player' })}
      />
    </Stack.Navigator>
  );
}
