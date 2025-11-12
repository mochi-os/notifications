// feat(auth): implement login-header based auth flow
// Note: Auth is handled by core app, this service only manages local auth state
import { useAuthStore } from '@/stores/auth-store'

const devConsole = globalThis.console

/**
 * Log errors in development mode only
 */
const logError = (context: string, error: unknown) => {
  if (import.meta.env.DEV) {
    devConsole?.error?.(`[Auth Service] ${context}`, error)
  }
}

/**
 * Validate current session by checking for login cookie
 *
 * This function checks if the current session is valid by:
 * 1. Checking for login in store
 * 2. Optionally calling /me endpoint to validate with backend
 * 3. Clearing auth if validation fails
 *
 * @returns Email if session is valid, null otherwise
 */
export const validateSession = async (): Promise<string | null> => {
  try {
    // Check if we have login
    const { login, email } = useAuthStore.getState()

    if (!login) {
      return null
    }

    // TODO: Uncomment when backend implements /me endpoint
    // try {
    //   const response: MeResponse = await authApi.me()
    //   // Update email if available from /me
    //   return response.user?.email || email || null
    // } catch (meError) {
    //   logError('Failed to fetch user profile from /me', meError)
    //   // If /me fails, clear auth
    //   useAuthStore.getState().clearAuth()
    //   return null
    // }

    // For now, just return the email from store
    // This assumes the credentials are valid if they exist
    return email || null
  } catch (error) {
    logError('Failed to validate session', error)
    // Clear auth on validation failure
    useAuthStore.getState().clearAuth()
    return null
  }
}

/**
 * Logout user
 *
 * This function:
 * 1. Optionally calls backend logout endpoint
 * 2. Clears all authentication state (cookies + store)
 * 3. Always succeeds (clears local state even if backend call fails)
 */
export const logout = async (): Promise<void> => {
  try {
    // TODO: Uncomment when backend implements logout endpoint
    // await authApi.logout()

    // Clear auth state (removes cookies and clears store)
    useAuthStore.getState().clearAuth()
  } catch (error) {
    logError('Logout failed', error)
    // Clear auth even if backend call fails
    useAuthStore.getState().clearAuth()
  }
}
