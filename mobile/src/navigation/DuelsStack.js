import { createNativeStackNavigator } from '@react-navigation/native-stack';
import DuelsListScreen from '../screens/DuelsListScreen';
import CreateChallengeScreen from '../screens/CreateChallengeScreen';
import DuelDetailScreen from '../screens/DuelDetailScreen';
import CounterScreen from '../screens/CounterScreen';
import DraftRoomScreen from '../screens/DraftRoomScreen';
import ResultsScreen from '../screens/ResultsScreen';
import { navHeader } from '../theme';

const Stack = createNativeStackNavigator();

export default function DuelsStack() {
  return (
    <Stack.Navigator screenOptions={navHeader}>
      <Stack.Screen name="DuelsList" component={DuelsListScreen} options={{ title: 'Duels' }} />
      <Stack.Screen
        name="CreateChallenge"
        component={CreateChallengeScreen}
        options={{ title: 'New Challenge' }}
      />
      <Stack.Screen name="DuelDetail" component={DuelDetailScreen} options={{ title: 'Challenge' }} />
      <Stack.Screen name="Counter" component={CounterScreen} options={{ title: 'Counter Offer' }} />
      <Stack.Screen name="DraftRoom" component={DraftRoomScreen} options={{ title: 'Live Draft' }} />
      <Stack.Screen name="Results" component={ResultsScreen} options={{ title: 'Result' }} />
    </Stack.Navigator>
  );
}
