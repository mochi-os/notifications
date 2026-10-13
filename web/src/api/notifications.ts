// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import {
  requestHelpers,
  type NotificationCategory,
  type NotificationTopic,
} from '@mochi/web'
import endpoints from '@/api/endpoints'

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
  // This page is a browser surface: a category with the web switch off is
  // not shown here.
  const response = await requestHelpers.getRaw<NotificationsListResponse>(
    endpoints.notifications.list,
    { params: { surface: 'web' } }
  )
  return response ?? { data: [], count: 0, total: 0 }
}

const markAsRead = async (id: string): Promise<void> => {
  const formData = new URLSearchParams()
  formData.append('id', id)

  await requestHelpers.post(endpoints.notifications.read, formData.toString(), {
    ...NO_TOAST,
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  })
}

const markAllAsRead = async (): Promise<void> => {
  await requestHelpers.post(endpoints.notifications.readAll, {}, NO_TOAST)
}

const clearAll = async (): Promise<void> => {
  await requestHelpers.post(endpoints.notifications.clearAll, {}, NO_TOAST)
}

// requestHelpers.get hands back what is inside the server's data envelope,
// not the envelope: reading .data off it again gave undefined, and the picker
// waited on categories that never arrived.
const listCategories = async (): Promise<NotificationCategory[]> => {
  const categories = await requestHelpers.get<NotificationCategory[] | null>(
    endpoints.categories.list
  )
  return categories ?? []
}

const lookupTopic = async (
  app: string,
  topic: string,
  object: string
): Promise<NotificationTopic | null> => {
  const params = new URLSearchParams({ app, topic, object })
  const row = await requestHelpers.get<NotificationTopic | null>(
    `${endpoints.topics.lookup}?${params.toString()}`
  )
  return row ?? null
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
