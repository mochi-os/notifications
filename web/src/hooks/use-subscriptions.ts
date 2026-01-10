import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { requestHelpers, toast, getErrorMessage } from '@mochi/common'

export interface SubscriptionDestination {
  type: 'account' | 'rss'
  target: string
}

export interface Subscription {
  id: number
  app: string
  type: string
  object: string
  label: string
  created: number
  destinations: SubscriptionDestination[]
}

interface SubscriptionsListResponse {
  data: Subscription[]
}

export const subscriptionKeys = {
  all: () => ['subscriptions'] as const,
  list: () => [...subscriptionKeys.all(), 'list'] as const,
}

// Fetch all subscriptions
async function listSubscriptions(): Promise<Subscription[]> {
  const response = await requestHelpers.get<SubscriptionsListResponse>('subscriptions/list')
  return response?.data ?? []
}

// Update subscription destinations
async function updateDestinations(id: number, destinations: SubscriptionDestination[]): Promise<void> {
  const formData = new URLSearchParams()
  formData.append('id', String(id))
  formData.append('destinations', JSON.stringify(destinations))

  await requestHelpers.post('subscriptions/update', formData.toString(), {
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  })
}

// Delete a subscription
async function deleteSubscription(id: number): Promise<void> {
  const formData = new URLSearchParams()
  formData.append('id', String(id))

  await requestHelpers.post('subscriptions/delete', formData.toString(), {
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  })
}

export interface UseSubscriptionsResult {
  subscriptions: Subscription[]
  isLoading: boolean
  updateDestinations: (id: number, destinations: SubscriptionDestination[]) => Promise<void>
  unsubscribe: (id: number) => Promise<void>
  isUpdating: boolean
  isDeleting: boolean
  refetch: () => void
}

export function useSubscriptions(): UseSubscriptionsResult {
  const queryClient = useQueryClient()

  const { data: subscriptions = [], isLoading, refetch } = useQuery({
    queryKey: subscriptionKeys.list(),
    queryFn: listSubscriptions,
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, destinations }: { id: number; destinations: SubscriptionDestination[] }) =>
      updateDestinations(id, destinations),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: subscriptionKeys.all() })
      toast.success('Subscription updated')
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to update subscription'))
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteSubscription(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: subscriptionKeys.all() })
      toast.success('Unsubscribed')
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to unsubscribe'))
    },
  })

  return {
    subscriptions,
    isLoading,
    updateDestinations: async (id: number, destinations: SubscriptionDestination[]) => {
      await updateMutation.mutateAsync({ id, destinations })
    },
    unsubscribe: async (id: number) => {
      await deleteMutation.mutateAsync(id)
    },
    isUpdating: updateMutation.isPending,
    isDeleting: deleteMutation.isPending,
    refetch: () => refetch(),
  }
}
