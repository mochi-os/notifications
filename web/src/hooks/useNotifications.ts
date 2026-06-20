// Copyright © 2026 Mochi OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useQueryWithError } from '@mochi/web'
import {
  notificationsApi,
  type NotificationsListResponse,
} from '@/api/notifications'

export const notificationKeys = {
  all: () => ['notifications'] as const,
  list: () => [...notificationKeys.all(), 'list'] as const,
}

export const useNotificationsQuery = () =>
  useQueryWithError<NotificationsListResponse, Error>({
    queryKey: notificationKeys.list(),
    queryFn: () => notificationsApi.list(),
  })

export const useMarkAsReadMutation = () => {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => notificationsApi.markAsRead(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.all() })
    },
  })
}

export const useMarkAllAsReadMutation = () => {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () => notificationsApi.markAllAsRead(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: notificationKeys.all() })
    },
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
