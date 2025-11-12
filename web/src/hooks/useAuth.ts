import { useAuthStore } from '@/stores/auth-store'

// feat(auth): implement login-header based auth flow
/**
 * Hook to access authentication state and actions
 * 
 * Provides convenient access to:
 * - Authentication state (login, email, loading, etc.)
 * - Authentication actions (syncFromCookie, logout, etc.)
 * 
 * Usage:
 * ```tsx
 * const { login, email, isAuthenticated, isLoading, logout } = useAuth()
 * 
 * if (isLoading) return <Loading />
 * if (!isAuthenticated) return <Login />
 * 
 * return <div>Welcome {email}</div>
 * ```
 */
export function useAuth() {
  const login = useAuthStore((state) => state.login)
  const email = useAuthStore((state) => state.email)
  const isLoading = useAuthStore((state) => state.isLoading)
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated)
  const isInitialized = useAuthStore((state) => state.isInitialized)

  const setLoading = useAuthStore((state) => state.setLoading)
  const syncFromCookie = useAuthStore((state) => state.syncFromCookie)
  const clearAuth = useAuthStore((state) => state.clearAuth)

  return {
    // State
    login,
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

/**
 * Check if user is authenticated
 */
export function useIsAuthenticated(): boolean {
  return useAuthStore((state) => state.isAuthenticated)
}

/**
 * Check if auth is loading
 */
export function useIsAuthLoading(): boolean {
  return useAuthStore((state) => state.isLoading)
}
