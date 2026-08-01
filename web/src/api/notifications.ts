// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import endpoints from '@/api/endpoints'
import { requestHelpers, type NotificationCategory, type NotificationTopic } from '@mochi/web'

const NO_TOAST = { mochi: { showGlobalErrorToast: false } } as const

export interface Notification {
  id: string
  app: string
  topic: string
  object: string
  content: string
  link: string
  sender?: string
  count: number
  created: number
  read: number
}

export interface NotificationsListResponse {
  data: Notification[]
  count: number
  total: number
}

const listNotifications = async (): Promise<NotificationsListResponse> => {
  const response = await requestHelpers.getRaw<NotificationsListResponse>(
    endpoints.notifications.list
  )
  return response ?? { data: [], count: 0, total: 0 }
}

const markAsRead = async (id: string): Promise<void> => {
  const formData = new URLSearchParams()
  formData.append('id', id)

  await requestHelpers.post(
    endpoints.notifications.read,
    formData.toString(),
    {
      ...NO_TOAST,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    }
  )
}

const markAllAsRead = async (): Promise<void> => {
  await requestHelpers.post(endpoints.notifications.readAll, {}, NO_TOAST)
}

const clearAll = async (): Promise<void> => {
  await requestHelpers.post(endpoints.notifications.clearAll, {}, NO_TOAST)
}

const listCategories = async (): Promise<NotificationCategory[]> => {
  const response = await requestHelpers.get<{ data?: NotificationCategory[] } | NotificationCategory[]>(
    endpoints.categories.list
  )
  return Array.isArray(response) ? response : (response.data ?? [])
}

const lookupTopic = async (
  app: string,
  topic: string,
  object: string
): Promise<NotificationTopic | null> => {
  const params = new URLSearchParams({ app, topic, object })
  const response = await requestHelpers.get<{ data?: NotificationTopic | null } | NotificationTopic | null>(
    `${endpoints.topics.lookup}?${params.toString()}`
  )
  if (!response) return null
  return 'data' in (response as object)
    ? ((response as { data?: NotificationTopic | null }).data ?? null)
    : (response as NotificationTopic)
}

const setTopicCategory = async (
  topic: NotificationTopic,
  category: string
): Promise<void> => {
  await requestHelpers.post(
    endpoints.topics.setCategory,
    { app: topic.app, topic: topic.topic, object: topic.object, category },
    NO_TOAST
  )
}

export const notificationsApi = {
  list: listNotifications,
  markAsRead,
  markAllAsRead,
  clearAll,
  listCategories,
  lookupTopic,
  setTopicCategory,
}
