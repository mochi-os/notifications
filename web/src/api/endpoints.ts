const endpoints = {
  notifications: {
    list: '-/list',
    read: '-/read',
    readAll: '-/read/all',
    clearAll: '-/clear/all',
  },
} as const

export default endpoints
