import { createNativeStackNavigator } from '@react-navigation/native-stack';
import DraftHubScreen from '../screens/DraftHubScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

// The DRAFT tab: a hub that routes into whichever duel is on the clock.
// (The actual draft room lives in the Duels stack so pushes/back work.)
export default function DraftStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="DraftHub" component={DraftHubScreen} options={{ headerShown: false }} />
    </Stack.Navigator>
  );
}
