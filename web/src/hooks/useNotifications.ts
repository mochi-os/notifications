import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notificationsApi, type NotificationsListResponse } from '@/api/notifications'

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
