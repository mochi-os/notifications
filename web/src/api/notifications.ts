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
  /** The path the app is served at, which locates its icon; '' for none. */
  path?: string
  topic: string
  object: string
  content: string
  link: string
  sender?: string
  count: number
  created: number
  read: number
}

// The rows alone: the page applies the notifications socket's frames to them
// (useNotificationsLiveRefresh), and the badge counts the server sends beside
// them are not kept, as no frame says how they change.
export interface NotificationsListResponse {
  data: Notification[]
}

const listNotifications = async (): Promise<NotificationsListResponse> => {
  // This page is a browser surface: a category with the web switch off is
  // not shown here.
  const response = await requestHelpers.getRaw<{ data?: Notification[] }>(
    endpoints.notifications.list,
    { params: { surface: 'web' } }
  )
  return { data: response?.data ?? [] }
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
  const row = await requestHelpers.get<NotificationTopic | null>(
    endpoints.topics.lookup,
    { params: { app, topic, object } }
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
