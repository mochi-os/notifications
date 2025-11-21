// feat(auth): implement login-header based auth flow
/**
 * Cookie utility functions using js-cookie library
 * 
 * Note: Authentication cookies (login, user_email) are set by mochi-core on sign-in.
 * This file provides utilities for reading auth cookies and managing UI preference cookies.
 * 
 * Cookie Names for Authentication:
 * - 'login': Primary credential (raw value used as Authorization header)
 * - 'user_email': User email address (for display and persistence)
 * 
 * UI Preference Cookies (set by this app):
 * - 'mochi-ui-theme': Theme preference (light/dark/system)
 * - 'dir': Text direction (ltr/rtl)
 * - 'font': Font preference
 * - 'layout_collapsible': Layout collapsible state
 * - 'layout_variant': Layout variant
 */
import Cookies from 'js-cookie'

/**
 * Get a cookie value by name
 */
export function getCookie(name: string): string | undefined {
  return Cookies.get(name)
}

/**
 * Set a cookie with name, value, and optional max age
 * 
 * Note: This is used for UI preferences only, not authentication cookies.
 * Authentication cookies are set by mochi-core.
 * 
 * @param name - Cookie name
 * @param value - Cookie value
 * @param maxAge - Max age in seconds (default: 7 days)
 * @param path - Cookie path (default: '/')
 */
export function setCookie(
  name: string,
  value: string,
  maxAge: number = 60 * 60 * 24 * 7, // 7 days
  path: string = '/'
): void {
  // Convert maxAge from seconds to days for js-cookie
  const expires = maxAge / (60 * 60 * 24)
  Cookies.set(name, value, { expires, path })
}

/**
 * Remove a cookie by name
 * 
 * @param name - Cookie name to remove
 * @param path - Cookie path (default: '/')
 * 
 * Note: If the cookie was set with a specific path, you must
 * provide the same path to remove it successfully.
 */
export function removeCookie(name: string, path: string = '/'): void {
  Cookies.remove(name, { path })
}
