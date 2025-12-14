import { useAuthStore } from '@mochi/common/stores/auth-store'

export const logout = async (): Promise<void> => {
  try {
    useAuthStore.getState().clearAuth()
  } catch (error) {
    console.error('Logout failed', error)
  }
}
