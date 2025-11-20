import { getCookie, removeCookie } from './cookies'

export type IdentityPrivacy = 'public' | 'private'

export interface ProfileCookieData {
  email?: string
  name?: string
  privacy?: IdentityPrivacy
}

const PROFILE_COOKIE = 'mochi_me'

const isIdentityPrivacy = (value: unknown): value is IdentityPrivacy =>
  value === 'public' || value === 'private'

const sanitizeProfile = (
  profile: ProfileCookieData
): ProfileCookieData => {
  const sanitized: ProfileCookieData = {}

  if (typeof profile.email === 'string' && profile.email.length > 0) {
    sanitized.email = profile.email
  }

  if (typeof profile.name === 'string' && profile.name.length > 0) {
    sanitized.name = profile.name
  }

  if (isIdentityPrivacy(profile.privacy)) {
    sanitized.privacy = profile.privacy
  }

  return sanitized
}

export const readProfileCookie = (): ProfileCookieData => {
  const raw = getCookie(PROFILE_COOKIE)
  if (!raw) {
    return {}
  }

  try {
    const parsed = JSON.parse(raw) as ProfileCookieData
    return sanitizeProfile(parsed)
  } catch {
    removeCookie(PROFILE_COOKIE, '/')
    return {}
  }
}

export const clearProfileCookie = (): void => {
  removeCookie(PROFILE_COOKIE, '/')
}

