import { createNavigationContainerRef } from '@react-navigation/native';

// A ref to the root NavigationContainer so non-screen code (push notification
// taps) can navigate. Guard every use with navigationRef.isReady().
export const navigationRef = createNavigationContainerRef();
