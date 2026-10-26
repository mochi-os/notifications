// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { onShellMessage, optimistic, useQueryWithError } from '@mochi/web'
import {
  notificationsApi,
  type Notification,
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

// The shell's bell holds the one notifications socket and passes each event
// down to the app frames, so the page refetches on that and opens no socket.
export const useNotificationsLiveRefresh = () => {
  const queryClient = useQueryClient()
  useEffect(
    () =>
      onShellMessage((message) => {
        if (message.type !== 'notification-update') return
        void queryClient.invalidateQueries({
          queryKey: notificationKeys.list(),
        })
      }),
    [queryClient]
  )
}

// A row goes read on the click and comes back unread if the server refuses;
// the caller says so. The server stamps `read` with the time in seconds.
const markRead =
  (which: (notification: Notification) => boolean) =>
  (old: NotificationsListResponse) => {
    const now = Math.floor(Date.now() / 1000)
    return {
      ...old,
      data: old.data.map((notification) =>
        notification.read === 0 && which(notification)
          ? { ...notification, read: now }
          : notification
      ),
    }
  }

export const useMarkAsReadMutation = () => {
  const queryClient = useQueryClient()
  const patch = optimistic(queryClient, (id: string) => [
    {
      filters: { queryKey: notificationKeys.list(), exact: true },
      update: markRead((notification) => notification.id === id),
    },
  ])
  return useMutation({
    mutationFn: (id: string) => notificationsApi.markAsRead(id),
    onMutate: patch.onMutate,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.all() })
    },
    onError: (_error, _id, context) => patch.rollback(context),
  })
}

export const useMarkAllAsReadMutation = () => {
  const queryClient = useQueryClient()
  const patch = optimistic<void>(queryClient, () => [
    {
      filters: { queryKey: notificationKeys.list(), exact: true },
      update: markRead(() => true),
    },
  ])
  return useMutation({
    mutationFn: () => notificationsApi.markAllAsRead(),
    onMutate: patch.onMutate,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.all() })
    },
    onError: (_error, _variables, context) => patch.rollback(context),
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
