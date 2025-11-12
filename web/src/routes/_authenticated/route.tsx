// feat(auth): implement login-header based auth flow
import { createFileRoute } from '@tanstack/react-router'
import { AuthenticatedLayout } from '@/components/layout/authenticated-layout'
import { useAuthStore } from '@/stores/auth-store'
import Cookies from 'js-cookie'

/**
 * Protected Route Guard
 *
 * This guard runs before any /_authenticated/* route loads.
 * It checks for authentication and redirects to login if not authenticated.
 *
 * Authentication Strategy:
 * 1. Sync store from cookies (handles page refresh)
 * 2. Check for login cookie directly
 * 3. Redirect to core auth app if no credentials found (cross-app navigation)
 */
export const Route = createFileRoute('/_authenticated')({
  beforeLoad: ({ location }) => {
    // Get auth state from store
    const store = useAuthStore.getState()

    // Sync from cookies if not initialized (handles page refresh)
    if (!store.isInitialized) {
      store.syncFromCookie()
    }

    // Check for login cookie directly (cookies are source of truth)
    const login = Cookies.get('login') || store.login

    // If not authenticated, redirect to core auth app (cross-app navigation)
    if (!login) {
      // Build redirect URL with return path
      const returnUrl = encodeURIComponent(location.href)
      const redirectUrl = `${import.meta.env.VITE_AUTH_SIGN_IN_URL}?redirect=${returnUrl}`

      // Use window.location.href for cross-app navigation (full page reload)
      window.location.href = redirectUrl

      // Return early to prevent route from loading
      return
    }

    // Authenticated, allow navigation
    return
  },
  component: AuthenticatedLayout,
})
