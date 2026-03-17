import { useNotificationWebSocket as useCommonNotificationWebSocket } from '@mochi/web'

// Compatibility wrapper to keep app-local imports stable while using the common singleton socket manager.
export function useNotificationWebSocket() {
  useCommonNotificationWebSocket()
}
