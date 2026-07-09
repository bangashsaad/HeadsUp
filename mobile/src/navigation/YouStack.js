import { createNativeStackNavigator } from '@react-navigation/native-stack';
import ProfileScreen from '../screens/ProfileScreen';
import SettingsScreen from '../screens/SettingsScreen';
import ChangePasswordScreen from '../screens/ChangePasswordScreen';
import LeaderboardScreen from '../screens/LeaderboardScreen';
import FriendsScreen from '../screens/FriendsScreen';
import SearchScreen from '../screens/SearchScreen';
import RequestsScreen from '../screens/RequestsScreen';
import UserProfileScreen from '../screens/UserProfileScreen';
import CoinHistoryScreen from '../screens/CoinHistoryScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

// The YOU tab: profile + the crew (friends, requests, leaderboard) + settings.
export default function YouStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="Profile" component={ProfileScreen} options={{ headerShown: false }} />
      <Stack.Screen name="Leaderboard" component={LeaderboardScreen} options={{ title: 'The Crew' }} />
      <Stack.Screen name="Friends" component={FriendsScreen} options={{ title: 'Friends' }} />
      <Stack.Screen name="Search" component={SearchScreen} options={{ title: 'Add Friends' }} />
      <Stack.Screen name="Requests" component={RequestsScreen} options={{ title: 'Friend Requests' }} />
      <Stack.Screen
        name="UserProfile"
        component={UserProfileScreen}
        options={({ route }) => ({ title: route.params?.username || 'Player' })}
      />
      <Stack.Screen name="CoinHistory" component={CoinHistoryScreen} options={{ title: 'Coin Wallet' }} />
      <Stack.Screen name="Settings" component={SettingsScreen} options={{ title: 'Settings' }} />
      <Stack.Screen name="ChangePassword" component={ChangePasswordScreen} options={{ title: 'Change Password' }} />
    </Stack.Navigator>
  );
}
