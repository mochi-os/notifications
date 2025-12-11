import Cookies from 'js-cookie'

export interface CookieOptions {
  maxAge?: number
  httpOnly?: boolean
  secure?: boolean
  sameSite?: 'strict' | 'lax' | 'none'
  path?: string
}

export function getCookie(name: string): string | undefined {
  return Cookies.get(name)
}

export function setCookie(
  name: string,
  value: string,
  options: CookieOptions = {}
): void {
  Cookies.set(name, value, options)
}

export function removeCookie(name: string, path: string = '/'): void {
  Cookies.remove(name, { path })
}
