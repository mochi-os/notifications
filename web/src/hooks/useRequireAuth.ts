import { useEffect } from 'react'
import { useAuth } from './useAuth'
import { getCookie } from '@/lib/cookies'

export function useRequireAuth() {
  const { isAuthenticated, isInitialized, isLoading } = useAuth()

  useEffect(() => {
    if (isInitialized && !isAuthenticated && !isLoading) {
      const token = getCookie('token')

      if (!token) {
        const currentPath = window.location.pathname + window.location.search
        const redirectUrl = `${import.meta.env.VITE_AUTH_LOGIN_URL}?redirect=${encodeURIComponent(currentPath)}`

        window.location.href = redirectUrl
      }
    }
  }, [isAuthenticated, isInitialized, isLoading])

  return {
    isLoading: !isInitialized || isLoading,
    isAuthenticated,
  }
}
