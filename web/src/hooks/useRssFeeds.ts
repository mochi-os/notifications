// Copyright © 2026 Mochi OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { useMutation, useQueryClient } from '@tanstack/react-query'
import { getAppPath, requestHelpers } from '@mochi/web'

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
        '-/rss/create',
        {
          name,
          add_to_existing: addToExisting ? '1' : '0',
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
      await requestHelpers.post('-/rss/delete', { id }, NO_TOAST)
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
      await requestHelpers.post('-/rss/rename', { id, name }, NO_TOAST)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
    },
  })
}

export function useToggleRssFeedEnabledMutation() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, enabled }: { id: string; enabled: boolean }) => {
      await requestHelpers.post(
        '-/rss/update',
        { id, enabled: enabled ? '1' : '0' },
        NO_TOAST
      )
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
    },
  })
}
