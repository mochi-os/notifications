// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  applyNotificationsFrame,
  entityWebsocketManager,
  useAuthStore,
  useQueryWithError,
  type NotificationFrame,
} from '@mochi/web'
import {
  notificationsApi,
  type NotificationsListResponse,
} from '@/api/notifications'

const notificationKeys = {
  all: () => ['notifications'] as const,
  list: () => [...notificationKeys.all(), 'list'] as const,
}

export const useNotificationsQuery = () =>
  useQueryWithError<NotificationsListResponse, Error>({
    queryKey: notificationKeys.list(),
    queryFn: () => notificationsApi.list(),
  })

// The page's own notifications socket, opened with this page's token. Core
// delivers the notifications app's frames only to connections a token for that
// app opened, and the page's is one, so it hears them as the bell does and
// applies each to the list it holds with the bell's reducer, rather than
// downloading the whole list again for every notification, read and open
// chat. A frame the reducer cannot take fetches the list, and so does every
// open of the socket, the first included: whatever was sent before it was
// there never arrived.
export const useNotificationsLiveRefresh = () => {
  const queryClient = useQueryClient()
  const ready = useAuthStore((state) => state.isInitialized)
  const token = useAuthStore((state) => state.token !== '')
  useEffect(() => {
    // Without the token the socket would be tagged with no app and hear
    // nothing the notifications app sends.
    if (!ready || !token) return
    return entityWebsocketManager.subscribe(
      'notifications',
      (frame) => {
        applyNotificationsFrame(
          queryClient,
          notificationKeys.list(),
          frame as NotificationFrame
        )
      },
      {
        open: () =>
          void queryClient.invalidateQueries({
            queryKey: notificationKeys.list(),
          }),
      }
    )
  }, [queryClient, ready, token])
}

// A read lands in the held list as it is asked for, as its frame lands it in
// every other tab, so the list is not fetched again for it: the frame this
// page's socket then hears changes nothing. A refused read fetches the list
// again, which says what is read, since a frame applied meanwhile would be lost
// by putting back what was there before the click.
const refused = (queryClient: ReturnType<typeof useQueryClient>) =>
  void queryClient.invalidateQueries({ queryKey: notificationKeys.list() })

export const useMarkAsReadMutation = () => {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => notificationsApi.markAsRead(id),
    onMutate: (id) => {
      applyNotificationsFrame(queryClient, notificationKeys.list(), {
        type: 'read',
        id,
      })
    },
    onError: () => refused(queryClient),
  })
}

export const useMarkAllAsReadMutation = () => {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () => notificationsApi.markAllAsRead(),
    onMutate: () => {
      applyNotificationsFrame(queryClient, notificationKeys.list(), {
        type: 'read_all',
      })
    },
    onError: () => refused(queryClient),
  })
}

export const useClearAllMutation = () => {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () => notificationsApi.clearAll(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.all() })
    },
  })
}
