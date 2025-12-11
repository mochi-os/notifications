import { useCallback } from 'react'
import { toast } from 'sonner'
import endpoints from '@/api/endpoints'
import { requestHelpers } from '@/lib/request'
import { useAuth } from './useAuth'
import { removeCookie } from '@/lib/cookies'

export function useLogout() {
  const { logout: clearAuth, setLoading, isLoading } = useAuth()

  const logout = useCallback(async () => {
    try {
      setLoading(true)

      try {
        await requestHelpers.get(endpoints.auth.logout)
      } catch (error) {
        if (import.meta.env.DEV) {
          console.error('[Logout] Backend logout failed:', error)
        }
      }

      removeCookie('token')
      removeCookie('mochi_me')
      clearAuth()

      toast.success('Logged out successfully')

      window.location.href = import.meta.env.VITE_AUTH_LOGIN_URL
    } catch (_error) {
      removeCookie('token')
      removeCookie('mochi_me')
      clearAuth()

      toast.error('Logged out (with errors)')

      window.location.href = import.meta.env.VITE_AUTH_LOGIN_URL
    } finally {
      setLoading(false)
    }
  }, [clearAuth, setLoading])

  return {
    logout,
    isLoggingOut: isLoading,
  }
}