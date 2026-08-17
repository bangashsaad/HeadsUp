import { View, Text, Pressable } from 'react-native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import HomeStack from './HomeStack';
import DuelsStack from './DuelsStack';
import DraftStack from './DraftStack';
import LiveStack from './LiveStack';
import FriendsStack from './FriendsStack';
import YouStack from './YouStack';
import { useTheme, fonts } from '../theme';
import { useDraftLive, useFriendReqs } from '../state/attention';
import { BlinkDot } from '../components/ui';
import { selection } from '../haptics';

const Tab = createBottomTabNavigator();

// Filled icon when the tab is focused, outline when not.
const ICONS = {
  HomeTab: { on: 'home', off: 'home-outline' },
  DuelsTab: { on: 'flame', off: 'flame-outline' },
  DraftTab: { on: 'timer', off: 'timer-outline' },
  LiveTab: { on: 'pulse', off: 'pulse-outline' },
  FriendsTab: { on: 'people', off: 'people-outline' },
  YouTab: { on: 'person-circle', off: 'person-circle-outline' },
};

// The Reimagined tab bar: 21px icons, 9px tracked caps, lime when focused,
// and a blinking red dot on DRAFT while a draft is live somewhere else.
function ReimaginedTabBar({ state, descriptors, navigation }) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const draftLive = useDraftLive();
  const friendReqs = useFriendReqs();

  return (
    <View
      style={{
        flexDirection: 'row',
        backgroundColor: colors.bg,
        borderTopWidth: 1,
        borderTopColor: colors.borderSubtle,
        paddingTop: 8,
        paddingHorizontal: 8,
        paddingBottom: Math.max(insets.bottom, 10),
      }}
    >
      {state.routes.map((route, index) => {
        const { options } = descriptors[route.key];
        const label = options.title ?? route.name;
        const focused = state.index === index;
        const color = focused ? colors.accent : colors.placeholder;
        const ic = ICONS[route.name] || ICONS.HomeTab;
        const showDot = route.name === 'DraftTab' && draftLive && !focused;
        const reqCount = route.name === 'FriendsTab' && !focused ? friendReqs : 0;

        function onPress() {
          const event = navigation.emit({ type: 'tabPress', target: route.key, canPreventDefault: true });
          if (!focused && !event.defaultPrevented) {
            selection();
            navigation.navigate(route.name, route.params);
          }
        }

        return (
          <Pressable
            key={route.key}
            onPress={onPress}
            accessibilityRole="button"
            accessibilityState={focused ? { selected: true } : {}}
            style={({ pressed }) => [
              { flex: 1, alignItems: 'center', gap: 3 },
              pressed && { transform: [{ scale: 0.92 }] },
            ]}
          >
            <View>
              <Ionicons name={focused ? ic.on : ic.off} size={21} color={color} />
              {showDot && <BlinkDot color={colors.danger} size={7} style={{ position: 'absolute', top: -2, right: -7 }} />}
              {reqCount > 0 && (
                <View
                  style={{
                    position: 'absolute',
                    top: -4,
                    right: -9,
                    minWidth: 14,
                    height: 14,
                    borderRadius: 7,
                    paddingHorizontal: 3,
                    backgroundColor: colors.cyan,
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  <Text style={{ color: '#0A0B10', fontSize: 9, fontFamily: fonts.bodyExtra }}>{reqCount}</Text>
                </View>
              )}
            </View>
            <Text
              style={{
                fontSize: 9,
                fontFamily: fonts.bodyExtra,
                letterSpacing: 0.5,
                color,
                textTransform: 'uppercase',
              }}
            >
              {label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export default function MainTabs() {
  return (
    <Tab.Navigator screenOptions={{ headerShown: false }} tabBar={(props) => <ReimaginedTabBar {...props} />}>
      <Tab.Screen name="HomeTab" component={HomeStack} options={{ title: 'Home' }} />
      <Tab.Screen name="DuelsTab" component={DuelsStack} options={{ title: 'Duels' }} />
      <Tab.Screen name="DraftTab" component={DraftStack} options={{ title: 'Draft' }} />
      <Tab.Screen name="LiveTab" component={LiveStack} options={{ title: 'Live' }} />
      <Tab.Screen name="FriendsTab" component={FriendsStack} options={{ title: 'Friends' }} />
      <Tab.Screen name="YouTab" component={YouStack} options={{ title: 'You' }} />
    </Tab.Navigator>
  );
}
