const endpoints = {
  notifications: {
    list: 'list',
    read: 'read',
    readAll: 'read/all',
    clearAll: 'clear/all',
  },
  auth: {
    code: '/_/code',
    verify: '/_/verify',
    identity: '/_/identity',
    logout: '/_/logout',
  },
} as const

export type Endpoints = typeof endpoints

export default endpoints
