// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { getAppPath, optimistic, requestHelpers } from '@mochi/web'
import endpoints from '@/api/endpoints'

export interface RssFeed {
  id: string
  name: string
  token: string
  created: number
  enabled: number
}

const NO_TOAST = { mochi: { showGlobalErrorToast: false } } as const

export function useCreateRssFeedMutation() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({
      name,
      addToExisting,
    }: {
      name: string
      addToExisting: boolean
    }) =>
      requestHelpers.post<RssFeed>(
        endpoints.rss.create,
        {
          name,
          existing: addToExisting ? '1' : '0',
        },
        NO_TOAST
      ),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
      queryClient.invalidateQueries({
        queryKey: ['destinations', getAppPath()],
      })
    },
  })
}

export function useDeleteRssFeedMutation() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      await requestHelpers.post(endpoints.rss.delete, { id }, NO_TOAST)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
      queryClient.invalidateQueries({
        queryKey: ['destinations', getAppPath()],
      })
    },
  })
}

export function useRenameRssFeedMutation() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, name }: { id: string; name: string }) => {
      await requestHelpers.post(endpoints.rss.rename, { id, name }, NO_TOAST)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
    },
  })
}

// The switch moves on the click and goes back if the server refuses; the
// dialog says so.
export function useToggleRssFeedEnabledMutation() {
  const queryClient = useQueryClient()
  const patch = optimistic(
    queryClient,
    ({ id, enabled }: { id: string; enabled: boolean }) => [
      {
        filters: { queryKey: ['rss-feeds'], exact: true },
        // The dialog reads the list defensively too (rss-dialog.tsx).
        update: (old: RssFeed[]) =>
          Array.isArray(old)
            ? old.map((feed) =>
                feed.id === id ? { ...feed, enabled: enabled ? 1 : 0 } : feed
              )
            : old,
      },
    ]
  )
  return useMutation({
    mutationFn: async ({ id, enabled }: { id: string; enabled: boolean }) => {
      await requestHelpers.post(
        endpoints.rss.update,
        { id, enabled: enabled ? '1' : '0' },
        NO_TOAST
      )
    },
    onMutate: patch.onMutate,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
    },
    onError: (_error, _variables, context) => patch.rollback(context),
  })
}
