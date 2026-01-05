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

export interface NotificationsListResponse {
  data: Notification[]
  count: number
  total: number
  rss: boolean
}

const listNotifications = async (): Promise<NotificationsListResponse> => {
  const response = await requestHelpers.getRaw<NotificationsListResponse>(
    endpoints.notifications.list
  )
  return response ?? { data: [], count: 0, total: 0, rss: false }
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

const clearAll = async (): Promise<void> => {
  await requestHelpers.post(endpoints.notifications.clearAll, {})
}

export const notificationsApi = {
  list: listNotifications,
  markAsRead,
  markAllAsRead,
  clearAll,
}

export default notificationsApi
