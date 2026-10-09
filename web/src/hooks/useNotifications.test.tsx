// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useNotificationsLiveRefresh } from './useNotifications'

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
