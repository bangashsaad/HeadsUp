import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Text } from 'react-native';
import FriendsStack from './FriendsStack';
import SportsStack from './SportsStack';
import DuelsStack from './DuelsStack';
import { colors } from '../theme';

const Tab = createBottomTabNavigator();

export default function MainTabs() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarStyle: { backgroundColor: colors.bg, borderTopColor: colors.border },
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.muted,
      }}
    >
      <Tab.Screen
        name="FriendsTab"
        component={FriendsStack}
        options={{
          title: 'Friends',
          tabBarIcon: () => <Text style={{ fontSize: 20 }}>👥</Text>,
        }}
      />
      <Tab.Screen
        name="DuelsTab"
        component={DuelsStack}
        options={{
          title: 'Duels',
          tabBarIcon: () => <Text style={{ fontSize: 20 }}>⚔️</Text>,
        }}
      />
      <Tab.Screen
        name="SportsTab"
        component={SportsStack}
        options={{
          title: 'Sports',
          tabBarIcon: () => <Text style={{ fontSize: 20 }}>🏟️</Text>,
        }}
      />
    </Tab.Navigator>
  );
}
