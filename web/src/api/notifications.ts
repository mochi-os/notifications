import endpoints from '@/api/endpoints'
import { requestHelpers } from '@mochi/common'

export interface Notification {
  id: string
  app: string
  category: string
  object: string
  content: string
  link: string
  count: number
  created: number
  read: number
}

export interface NotificationCount {
  count: number
  total: number
}

const listNotifications = async (): Promise<Notification[]> => {
  const response = await requestHelpers.get<Notification[]>(
    endpoints.notifications.list
  )
  return response ?? []
}

const getNotificationCount = async (): Promise<NotificationCount> => {
  const response = await requestHelpers.get<NotificationCount>(
    endpoints.notifications.count
  )
  return response ?? { count: 0, total: 0 }
}

const markAsRead = async (id: string): Promise<void> => {
  const formData = new URLSearchParams()
  formData.append('id', id)

  await requestHelpers.post(
    endpoints.notifications.read,
    formData.toString(),
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    }
  )
}

const markAllAsRead = async (): Promise<void> => {
  await requestHelpers.post(endpoints.notifications.readAll, {})
}

export const notificationsApi = {
  list: listNotifications,
  count: getNotificationCount,
  markAsRead,
  markAllAsRead,
}

export default notificationsApi
