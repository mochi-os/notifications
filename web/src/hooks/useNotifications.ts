import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notificationsApi, type NotificationsListResponse } from '@/api/notifications'
import { requestHelpers } from '@mochi/common'

export const notificationKeys = {
  all: () => ['notifications'] as const,
  list: () => [...notificationKeys.all(), 'list'] as const,
}

export const useNotificationsQuery = () =>
  useQuery<NotificationsListResponse>({
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

interface TokenCreateResponse {
  token: string
}

export const useRssTokenMutation = () => {
  return useMutation({
    mutationFn: async () => {
      const response = await requestHelpers.post<TokenCreateResponse>(
        '/settings/user/account/token/create',
        { name: 'Notifications RSS' }
      )
      return response.token
    },
  })
}
