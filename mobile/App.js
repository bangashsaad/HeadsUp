import { StatusBar } from 'expo-status-bar';
import { NavigationContainer, DefaultTheme } from '@react-navigation/native';
import { ActivityIndicator, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useFonts } from 'expo-font';
import {
  Archivo_400Regular,
  Archivo_500Medium,
  Archivo_600SemiBold,
  Archivo_700Bold,
  Archivo_800ExtraBold,
  Archivo_900Black,
  Archivo_900Black_Italic,
} from '@expo-google-fonts/archivo';
import {
  BarlowCondensed_500Medium,
  BarlowCondensed_600SemiBold,
  BarlowCondensed_700Bold,
  BarlowCondensed_700Bold_Italic,
  BarlowCondensed_800ExtraBold,
  BarlowCondensed_800ExtraBold_Italic,
} from '@expo-google-fonts/barlow-condensed';
import { AuthProvider, useAuth } from './src/auth/AuthContext';
import { ThemeProvider, useTheme } from './src/theme';
import { PreferencesProvider } from './src/prefs';
import AuthStack from './src/navigation/AuthStack';
import MainTabs from './src/navigation/MainTabs';
import PushTapRouter from './src/navigation/PushTapRouter';
import { navigationRef } from './src/navigation/ref';

function RootNavigator() {
  const { user, loading } = useAuth();
  const { colors, scheme } = useTheme();

  const navTheme = {
    ...DefaultTheme,
    dark: scheme === 'dark',
    colors: {
      ...DefaultTheme.colors,
      background: colors.bg,
      card: colors.bg,
      text: colors.text,
      border: colors.border,
      primary: colors.accent,
    },
  };

  if (loading) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.bg, justifyContent: 'center', alignItems: 'center' }}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  return (
    <NavigationContainer ref={navigationRef} theme={navTheme}>
      {user ? <MainTabs /> : <AuthStack />}
      {user ? <PushTapRouter /> : null}
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />
    </NavigationContainer>
  );
}

export default function App() {
  const [fontsLoaded, fontsError] = useFonts({
    Archivo_400Regular,
    Archivo_500Medium,
    Archivo_600SemiBold,
    Archivo_700Bold,
    Archivo_800ExtraBold,
    Archivo_900Black,
    Archivo_900Black_Italic,
    BarlowCondensed_500Medium,
    BarlowCondensed_600SemiBold,
    BarlowCondensed_700Bold,
    BarlowCondensed_700Bold_Italic,
    BarlowCondensed_800ExtraBold,
    BarlowCondensed_800ExtraBold_Italic,
  });

  // Hold on the dark bg until the brand faces are in; if loading ever fails
  // we render anyway rather than strand the user on a blank screen.
  if (!fontsLoaded && !fontsError) {
    return <View style={{ flex: 1, backgroundColor: '#0A0B10' }} />;
  }

  return (
    <SafeAreaProvider>
      <ThemeProvider>
        <PreferencesProvider>
          <AuthProvider>
            <RootNavigator />
          </AuthProvider>
        </PreferencesProvider>
      </ThemeProvider>
    </SafeAreaProvider>
  );
}
