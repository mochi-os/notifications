import { useCallback } from 'react'
import { toast } from 'sonner'
import Cookies from 'js-cookie'
import { useAuth } from './useAuth'

export function useLogout() {
  const { logout: clearAuth, setLoading, isLoading } = useAuth()

  const logout = useCallback(async () => {
    try {
      setLoading(true)

      // Remove both cookies
      Cookies.remove('login', { path: '/' })
      Cookies.remove('user_email', { path: '/' })

      // Clear auth store
      clearAuth()

      // Show success message
      toast.success('Logged out successfully')

      // Redirect to core auth app (cross-app navigation)
      window.location.href = import.meta.env.VITE_AUTH_SIGN_IN_URL
    } catch (error) {
      // Even if backend call fails, clear local auth
      Cookies.remove('login', { path: '/' })
      Cookies.remove('user_email', { path: '/' })
      clearAuth()

      toast.error('Logged out (with errors)')

      // Redirect to core auth app (cross-app navigation)
      window.location.href = import.meta.env.VITE_AUTH_SIGN_IN_URL
    } finally {
      setLoading(false)
    }
  }, [clearAuth, setLoading])

  return {
    logout,
    isLoggingOut: isLoading,
  }
}
