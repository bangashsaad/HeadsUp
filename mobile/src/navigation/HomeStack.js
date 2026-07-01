import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HomeScreen from '../screens/HomeScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

export default function HomeStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="Home" component={HomeScreen} options={{ title: 'Heads Up' }} />
    </Stack.Navigator>
  );
}
