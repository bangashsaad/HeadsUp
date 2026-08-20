import { createNativeStackNavigator } from '@react-navigation/native-stack';
import ProfileScreen from '../screens/ProfileScreen';
import SettingsScreen from '../screens/SettingsScreen';
import ChangePasswordScreen from '../screens/ChangePasswordScreen';
import BlockedScreen from '../screens/BlockedScreen';
import LeaderboardScreen from '../screens/LeaderboardScreen';
import UserProfileScreen from '../screens/UserProfileScreen';
import CoinHistoryScreen from '../screens/CoinHistoryScreen';
import VerifyEmailScreen from '../screens/VerifyEmailScreen';
import FriendGroupsScreen from '../screens/FriendGroupsScreen';
import { useNavHeader } from '../theme';

const Stack = createNativeStackNavigator();

// The YOU tab: profile + friends (list, requests, standings) + settings.
export default function YouStack() {
  const header = useNavHeader();
  return (
    <Stack.Navigator screenOptions={header}>
      <Stack.Screen name="Profile" component={ProfileScreen} options={{ headerShown: false }} />
      <Stack.Screen name="Leaderboard" component={LeaderboardScreen} options={{ title: 'Friend Standings' }} />
      <Stack.Screen
        name="UserProfile"
        component={UserProfileScreen}
        options={({ route }) => ({ title: route.params?.username || 'Player' })}
      />
      <Stack.Screen name="CoinHistory" component={CoinHistoryScreen} options={{ title: 'Coin Wallet' }} />
      <Stack.Screen name="VerifyEmail" component={VerifyEmailScreen} options={{ title: 'Verify Email' }} />
      <Stack.Screen name="FriendGroups" component={FriendGroupsScreen} options={{ title: 'Friend Groups' }} />
      <Stack.Screen name="Settings" component={SettingsScreen} options={{ title: 'Settings' }} />
      <Stack.Screen name="ChangePassword" component={ChangePasswordScreen} options={{ title: 'Change Password' }} />
      <Stack.Screen name="Blocked" component={BlockedScreen} options={{ title: 'Blocked Players' }} />
    </Stack.Navigator>
  );
}
