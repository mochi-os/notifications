// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useToggleRssFeedEnabledMutation } from './useRssFeeds'

const post = vi.hoisted(() => vi.fn())

vi.mock('@mochi/web', async (importOriginal) => {
  const original = await importOriginal<typeof import('@mochi/web')>()
  return { ...original, requestHelpers: { ...original.requestHelpers, post } }
})

// The Notify by default switch moves on the click and goes back if the
// server refuses.
describe('useToggleRssFeedEnabledMutation', () => {
  let refuse: (error: unknown) => void
  beforeEach(() => {
    post.mockReset()
    post.mockImplementation(
      () =>
        new Promise((_resolve, reject) => {
          refuse = reject
        })
    )
  })

  it('switches at once and back when refused', async () => {
    const client = new QueryClient()
    client.setQueryData(
      ['rss-feeds'],
      [
        { id: 'r1', enabled: 0 },
        { id: 'r2', enabled: 0 },
      ]
    )
    const view = renderHook(() => useToggleRssFeedEnabledMutation(), {
      wrapper: ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={client}>{children}</QueryClientProvider>
      ),
    })
    const enabled = () =>
      client
        .getQueryData<{ enabled: number }[]>(['rss-feeds'])
        ?.map((feed) => feed.enabled)

    act(() => view.result.current.mutate({ id: 'r1', enabled: true }))
    await waitFor(() => expect(enabled()).toEqual([1, 0]))

    act(() => refuse(new Error('refused')))
    await waitFor(() => expect(view.result.current.isError).toBe(true))
    expect(enabled()).toEqual([0, 0])
  })
})
