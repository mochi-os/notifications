import { create } from 'zustand'
import { removeCookie, getCookie } from '@/lib/cookies'
import { readProfileCookie, clearProfileCookie } from '@/lib/profile-cookie'

const TOKEN_COOKIE = 'token'

interface AuthState {
  token: string
  email: string
  isLoading: boolean
  isInitialized: boolean

  isAuthenticated: boolean

  setLoading: (isLoading: boolean) => void
  syncFromCookie: () => void
  clearAuth: () => void
  initialize: () => void
}

export const useAuthStore = create<AuthState>()((set, get) => {
  const initialToken = getCookie(TOKEN_COOKIE) || ''
  const profile = readProfileCookie()
  const initialEmail = profile.email || ''

  return {
    token: initialToken,
    email: initialEmail,
    isLoading: false,
    isInitialized: false,
    isAuthenticated: Boolean(initialToken),

    setLoading: (isLoading) => {
      set({ isLoading })
    },

    syncFromCookie: () => {
      const cookieToken = getCookie(TOKEN_COOKIE) || ''
      const profile = readProfileCookie()
      const cookieEmail = profile.email || ''
      const storeToken = get().token
      const storeEmail = get().email

      if (cookieToken !== storeToken || cookieEmail !== storeEmail) {
        set({
          token: cookieToken,
          email: cookieEmail,
          isAuthenticated: Boolean(cookieToken),
          isInitialized: true,
        })
      } else {
        set({ isInitialized: true })
      }
    },

    clearAuth: () => {
      removeCookie(TOKEN_COOKIE)
      clearProfileCookie()

      set({
        token: '',
        email: '',
        isAuthenticated: false,
        isLoading: false,
        isInitialized: true,
      })
    },

    initialize: () => {
      get().syncFromCookie()
    },
  }
})
