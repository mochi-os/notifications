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
