import { createNativeStackNavigator } from '@react-navigation/native-stack';
import DuelsListScreen from '../screens/DuelsListScreen';
import CreateChallengeScreen from '../screens/CreateChallengeScreen';
import DuelDetailScreen from '../screens/DuelDetailScreen';
import CounterScreen from '../screens/CounterScreen';
import DraftRoomScreen from '../screens/DraftRoomScreen';
import ResultsScreen from '../screens/ResultsScreen';
import LiveMatchupScreen from '../screens/LiveMatchupScreen';
import PlayerProfileScreen from '../screens/PlayerProfileScreen';
import UserProfileScreen from '../screens/UserProfileScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

export default function DuelsStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="DuelsList" component={DuelsListScreen} options={{ headerShown: false }} />
      <Stack.Screen name="CreateChallenge" component={CreateChallengeScreen} options={{ title: 'New Challenge' }} />
      <Stack.Screen name="DuelDetail" component={DuelDetailScreen} options={{ title: 'Challenge' }} />
      <Stack.Screen name="Counter" component={CounterScreen} options={{ title: 'Counter Offer' }} />
      <Stack.Screen name="DraftRoom" component={DraftRoomScreen} options={{ title: 'Draft Room' }} />
      <Stack.Screen name="Results" component={ResultsScreen} options={{ title: 'Result' }} />
      <Stack.Screen name="LiveMatchup" component={LiveMatchupScreen} options={{ title: 'Live Matchup' }} />
      <Stack.Screen
        name="PlayerProfile"
        component={PlayerProfileScreen}
        options={({ route }) => ({ title: route.params?.name || 'Player' })}
      />
      <Stack.Screen
        name="UserProfile"
        component={UserProfileScreen}
        options={({ route }) => ({ title: route.params?.username || 'Player' })}
      />
    </Stack.Navigator>
  );
}
