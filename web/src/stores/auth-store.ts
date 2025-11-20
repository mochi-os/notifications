// feat(auth): implement login-header based auth flow
import { create } from 'zustand'
import Cookies from 'js-cookie'
import { readProfileCookie, clearProfileCookie } from '@/lib/profile-cookie'

/**
 * Cookie names for authentication
 * - login: Primary credential (raw value used as Authorization header)
 * - mochi_me: Consolidated profile data (email, name, privacy)
 */
const LOGIN_COOKIE = 'login'

/**
 * Authentication state interface
 *
 * Authentication Strategy:
 * - login: Primary credential (raw value from backend, used as-is in Authorization header)
 * - email: User email for display purposes
 * - isAuthenticated: Computed from presence of login
 *
 * Feature apps only read and remove cookies (never set them).
 * Cookies are set by mochi-core on sign-in.
 */
interface AuthState {
  // State
  login: string // Primary credential (raw login value)
  email: string // User email for display
  isLoading: boolean
  isInitialized: boolean

  // Computed
  isAuthenticated: boolean

  // Actions
  setLoading: (isLoading: boolean) => void
  syncFromCookie: () => void
  clearAuth: () => void
  initialize: () => void
}

/**
 * Auth Store using Zustand
 *
 * This store manages authentication state with the following strategy:
 * 1. Primary credential: login (stored in 'login' cookie, set by mochi-core)
 * 2. User profile: email/name/privacy (stored in 'mochi_me' cookie, set by mochi-core)
 * 3. Cookies are the source of truth (survive page refresh)
 * 4. Store provides fast in-memory access
 *
 * Authentication Flow:
 * - On app boot: Read cookies and hydrate store
 * - On requests: Use 'login' as Authorization header
 * - On page load: Sync state from cookies
 * - On logout: Clear both cookies and state
 */
export const useAuthStore = create<AuthState>()((set, get) => {
  // Initialize from cookies on store creation
  const initialLogin = Cookies.get(LOGIN_COOKIE) || ''
  const profile = readProfileCookie()
  const initialEmail = profile.email || ''

  return {
    // Initial state from cookies
    login: initialLogin,
    email: initialEmail,
    isLoading: false,
    isInitialized: false,
    // Authenticated if we have login
    isAuthenticated: Boolean(initialLogin),

    /**
     * Set loading state
     */
    setLoading: (isLoading) => {
      set({ isLoading })
    },

    /**
     * Sync store state from cookies
     * Call this on route navigation or app mount to ensure consistency
     */
    syncFromCookie: () => {
      const cookieLogin = Cookies.get(LOGIN_COOKIE) || ''
      const profile = readProfileCookie()
      const cookieEmail = profile.email || ''
      const storeLogin = get().login
      const storeEmail = get().email

      // If cookies differ from store, sync to store (cookies are source of truth)
      if (cookieLogin !== storeLogin || cookieEmail !== storeEmail) {
        set({
          login: cookieLogin,
          email: cookieEmail,
          isAuthenticated: Boolean(cookieLogin),
          isInitialized: true,
        })
      } else {
        set({ isInitialized: true })
      }
    },

    /**
     * Clear all authentication state
     * Call this on logout or when session is invalidated
     */
    clearAuth: () => {
      // Remove cookies (feature apps can remove cookies)
      Cookies.remove(LOGIN_COOKIE, { path: '/' })
      clearProfileCookie()

      set({
        login: '',
        email: '',
        isAuthenticated: false,
        isLoading: false,
        isInitialized: true,
      })
    },

    /**
     * Initialize auth state from cookies
     * Call this once on app mount
     */
    initialize: () => {
      get().syncFromCookie()
    },
  }
})
