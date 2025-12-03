import { useAuthStore } from '@/stores/auth-store'

export function useAuth() {
  const token = useAuthStore((state) => state.token)
  const email = useAuthStore((state) => state.email)
  const isLoading = useAuthStore((state) => state.isLoading)
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated)
  const isInitialized = useAuthStore((state) => state.isInitialized)

  const setLoading = useAuthStore((state) => state.setLoading)
  const syncFromCookie = useAuthStore((state) => state.syncFromCookie)
  const clearAuth = useAuthStore((state) => state.clearAuth)

  return {
    token,
    email,
    isLoading,
    isAuthenticated,
    isInitialized,

    // Actions
    setLoading,
    syncFromCookie,
    logout: clearAuth,
  }
}

export function useIsAuthenticated(): boolean {
  return useAuthStore((state) => state.isAuthenticated)
}

export function useIsAuthLoading(): boolean {
  return useAuthStore((state) => state.isLoading)
}
