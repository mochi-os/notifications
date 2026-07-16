// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import endpoints from '@/api/endpoints'
import { requestHelpers } from '@mochi/web'

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

export const notificationsApi = {
  list: listNotifications,
  markAsRead,
  markAllAsRead,
  clearAll,
}
