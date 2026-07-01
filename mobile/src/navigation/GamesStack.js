import { Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import GamesScreen from '../screens/GamesScreen';
import GameDetailScreen from '../screens/GameDetailScreen';
import PlayerProfileScreen from '../screens/PlayerProfileScreen';
import PlayerSearchScreen from '../screens/PlayerSearchScreen';
import { useNavHeader, useTheme } from '../theme';

const Stack = createNativeStackNavigator();

export default function GamesStack() {
  const header = useNavHeader();
  const { colors } = useTheme();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen
        name="Games"
        component={GamesScreen}
        options={({ navigation }) => ({
          title: 'Games',
          headerRight: () => (
            <Pressable onPress={() => navigation.navigate('PlayerSearch')} hitSlop={10}>
              <Ionicons name="search" size={22} color={colors.text} />
            </Pressable>
          ),
        })}
      />
      <Stack.Screen name="GameDetail" component={GameDetailScreen} options={{ title: 'Matchup' }} />
      <Stack.Screen name="PlayerSearch" component={PlayerSearchScreen} options={{ title: 'Search Players' }} />
      <Stack.Screen
        name="PlayerProfile"
        component={PlayerProfileScreen}
        options={({ route }) => ({ title: route.params?.name || 'Player' })}
      />
    </Stack.Navigator>
  );
}
