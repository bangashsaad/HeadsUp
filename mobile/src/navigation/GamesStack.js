import { Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import GamesScreen from '../screens/GamesScreen';
import GameDetailScreen from '../screens/GameDetailScreen';
import PlayerProfileScreen from '../screens/PlayerProfileScreen';
import PlayerSearchScreen from '../screens/PlayerSearchScreen';
import CompareScreen from '../screens/CompareScreen';
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
      <Stack.Screen
        name="PlayerSearch"
        component={PlayerSearchScreen}
        options={({ navigation }) => ({
          title: 'Search Players',
          headerRight: () => (
            <Pressable onPress={() => navigation.navigate('Compare')} hitSlop={10}>
              <Ionicons name="git-compare-outline" size={22} color={colors.text} />
            </Pressable>
          ),
        })}
      />
      <Stack.Screen name="Compare" component={CompareScreen} options={{ title: 'Compare Players' }} />
      <Stack.Screen
        name="PlayerProfile"
        component={PlayerProfileScreen}
        options={({ route }) => ({ title: route.params?.name || 'Player' })}
      />
    </Stack.Navigator>
  );
}
