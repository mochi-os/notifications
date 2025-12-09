export const APP_ROUTES = {
  // Chat app
  CHAT: {
    BASE: '/chat/',
    HOME: '/chat/',
  },
  // Friends app
  FRIENDS: {
    BASE: '/friends/',
    HOME: '/friends/',
  },
  // Home app
  HOME: {
    BASE: '/',
    HOME: '/',
  },
  // Feeds app
  FEEDS: {
    BASE: '/feeds/',
    HOME: '/feeds/',
  },
  // Forums app
  FORUMS: {
    BASE: '/forums/',
    HOME: '/forums/',
  },
  // Notifications app
  NOTIFICATIONS: {
    BASE: './',
    HOME: './',
  },
  // Template app
  TEMPLATE: {
    BASE: '/template/',
    HOME: '/template/',
  },
  // Settings app
  SETTINGS: {
    BASE: '/settings/',
    HOME: '/settings/',
    USER: {
      ACCOUNT: '/user/account',
      SESSIONS: '/user/sessions',
      PREFERENCES: '/user/preferences',
    },
    SYSTEM: {
      SETTINGS: '/system/settings',
      USERS: '/system/users',
      STATUS: '/system/status',
    },
    DOMAINS: '/domains',
  }
} as const

export type AppRoutes = typeof APP_ROUTES
