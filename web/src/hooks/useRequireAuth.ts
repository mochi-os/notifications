import { useEffect } from 'react'
import Cookies from 'js-cookie'
import { useAuth } from './useAuth'

export function useRequireAuth() {
  const { isAuthenticated, isInitialized, isLoading } = useAuth()

  useEffect(() => {
    // Only redirect once initialization is complete
    if (isInitialized && !isAuthenticated && !isLoading) {
      // Check login cookie directly (cookies are source of truth)
      const login = Cookies.get('login')
      
      if (!login) {
        // Save current location for redirect after login
        const currentPath = window.location.pathname + window.location.search
        const redirectUrl = `${import.meta.env.VITE_AUTH_SIGN_IN_URL}?redirect=${encodeURIComponent(currentPath)}`

        // Use window.location.href for cross-app navigation (full page reload)
        window.location.href = redirectUrl
      }
    }
  }, [isAuthenticated, isInitialized, isLoading])

  return {
    isLoading: !isInitialized || isLoading,
    isAuthenticated,
  }
}
