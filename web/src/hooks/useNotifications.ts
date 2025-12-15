import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notificationsApi, type Notification } from '@/api/notifications'

export const notificationKeys = {
  all: () => ['notifications'] as const,
  list: () => [...notificationKeys.all(), 'list'] as const,
  count: () => [...notificationKeys.all(), 'count'] as const,
}

export const useNotificationsQuery = () =>
  useQuery<Notification[]>({
    queryKey: notificationKeys.list(),
    queryFn: () => notificationsApi.list(),
  })

export const useNotificationCountQuery = () =>
  useQuery({
    queryKey: notificationKeys.count(),
    queryFn: () => notificationsApi.count(),
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
