import * as Haptics from 'expo-haptics';

// A thin gate over expo-haptics so a single preference can mute all feedback.
let enabled = true;

export function setHapticsEnabled(value) {
  enabled = value;
}

export function impact(style) {
  if (enabled) Haptics.impactAsync(style ?? Haptics.ImpactFeedbackStyle.Light).catch(() => {});
}

export function selection() {
  if (enabled) Haptics.selectionAsync().catch(() => {});
}

export function notify(type) {
  if (enabled) Haptics.notificationAsync(type ?? Haptics.NotificationFeedbackType.Success).catch(() => {});
}

export const ImpactStyle = Haptics.ImpactFeedbackStyle;
export const NotifyType = Haptics.NotificationFeedbackType;
