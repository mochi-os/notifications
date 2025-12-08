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
    BASE: '/home/',
    HOME: '/home/',
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
} as const

export type AppRoutes = typeof APP_ROUTES
