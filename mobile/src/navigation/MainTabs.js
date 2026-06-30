import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Ionicons } from '@expo/vector-icons';
import FriendsStack from './FriendsStack';
import SportsStack from './SportsStack';
import DuelsStack from './DuelsStack';
import ProfileStack from './ProfileStack';
import { useTheme } from '../theme';

const Tab = createBottomTabNavigator();

// Filled icon when the tab is focused, outline when not.
const ICONS = {
  FriendsTab: { on: 'people', off: 'people-outline' },
  DuelsTab: { on: 'flame', off: 'flame-outline' },
  SportsTab: { on: 'basketball', off: 'basketball-outline' },
  ProfileTab: { on: 'person-circle', off: 'person-circle-outline' },
};

export default function MainTabs() {
  const { colors } = useTheme();
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarStyle: { backgroundColor: colors.bg, borderTopColor: colors.border, borderTopWidth: 1 },
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.muted,
        tabBarLabelStyle: { fontSize: 11, fontWeight: '700' },
        tabBarIcon: ({ focused, color, size }) => {
          const ic = ICONS[route.name] || ICONS.FriendsTab;
          return <Ionicons name={focused ? ic.on : ic.off} size={size ?? 22} color={color} />;
        },
      })}
    >
      <Tab.Screen name="FriendsTab" component={FriendsStack} options={{ title: 'Friends' }} />
      <Tab.Screen name="DuelsTab" component={DuelsStack} options={{ title: 'Duels' }} />
      <Tab.Screen name="SportsTab" component={SportsStack} options={{ title: 'Sports' }} />
      <Tab.Screen name="ProfileTab" component={ProfileStack} options={{ title: 'Profile' }} />
    </Tab.Navigator>
  );
}
