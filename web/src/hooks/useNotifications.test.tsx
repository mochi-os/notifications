// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { notificationsApi } from '@/api/notifications'
import {
  useMarkAllAsReadMutation,
  useMarkAsReadMutation,
  useNotificationsLiveRefresh,
} from './useNotifications'

vi.mock('@/api/notifications', () => ({
  notificationsApi: { markAsRead: vi.fn(), markAllAsRead: vi.fn() },
}))

type Listener = (message: { type: string }) => void
let listeners: Listener[] = []

// Partial mock: only the shell message bus is replaced, so a test can play the
// bell's broadcast without a shell around the page.
vi.mock('@mochi/web', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@mochi/web')>()
  return {
    ...actual,
    onShellMessage: (listener: Listener) => {
      listeners.push(listener)
      return () => {
        listeners = listeners.filter((entry) => entry !== listener)
      }
    },
  }
})

function mount() {
  const queryClient = new QueryClient()
  const invalidate = vi.spyOn(queryClient, 'invalidateQueries')
  const view = renderHook(() => useNotificationsLiveRefresh(), {
    wrapper: ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    ),
  })
  return { invalidate, view }
}

describe('useNotificationsLiveRefresh', () => {
  beforeEach(() => {
    listeners = []
  })

  it('refetches the list when the bell passes on a notification event', () => {
    const { invalidate } = mount()
    for (const listener of listeners) listener({ type: 'notification-update' })
    expect(invalidate).toHaveBeenCalledWith({
      queryKey: ['notifications', 'list'],
    })
  })

  it('leaves the list alone on any other shell message', () => {
    const { invalidate } = mount()
    for (const listener of listeners) listener({ type: 'navigate' })
    expect(invalidate).not.toHaveBeenCalled()
  })

  it('stops listening once the page is gone', () => {
    const { view } = mount()
    expect(listeners).toHaveLength(1)
    view.unmount()
    expect(listeners).toHaveLength(0)
  })
})

// A row goes read on the click and comes back unread if the server refuses.
describe('marking read', () => {
  const unread = (id: string) => ({
    id,
    app: 'chat',
    topic: 'message',
    object: 'o1',
    content: 'Hello',
    link: '',
    count: 1,
    created: 1,
    read: 0,
  })

  let refuse: (error: unknown) => void
  beforeEach(() => {
    const waiting = () =>
      new Promise<void>((_resolve, reject) => {
        refuse = reject
      })
    vi.mocked(notificationsApi.markAsRead).mockImplementation(waiting)
    vi.mocked(notificationsApi.markAllAsRead).mockImplementation(waiting)
  })

  function mountWithList<T>(hook: () => T) {
    const queryClient = new QueryClient()
    queryClient.setQueryData(['notifications', 'list'], {
      data: [unread('n1'), unread('n2')],
      count: 2,
      total: 2,
    })
    const view = renderHook(hook, {
      wrapper: ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={queryClient}>
          {children}
        </QueryClientProvider>
      ),
    })
    const readIds = () =>
      queryClient
        .getQueryData<{ data: { id: string; read: number }[] }>([
          'notifications',
          'list',
        ])
        ?.data.filter((n) => n.read !== 0)
        .map((n) => n.id)
    return { view, readIds }
  }

  it('marks one read at once and unread again when refused', async () => {
    const { view, readIds } = mountWithList(() => useMarkAsReadMutation())
    act(() => view.result.current.mutate('n1'))
    await waitFor(() => expect(readIds()).toEqual(['n1']))

    act(() => refuse(new Error('refused')))
    await waitFor(() => expect(view.result.current.isError).toBe(true))
    expect(readIds()).toEqual([])
  })

  it('marks all read at once and unread again when refused', async () => {
    const { view, readIds } = mountWithList(() => useMarkAllAsReadMutation())
    act(() => view.result.current.mutate())
    await waitFor(() => expect(readIds()).toEqual(['n1', 'n2']))

    act(() => refuse(new Error('refused')))
    await waitFor(() => expect(view.result.current.isError).toBe(true))
    expect(readIds()).toEqual([])
  })
})
