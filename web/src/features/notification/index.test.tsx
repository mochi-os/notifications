// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { i18n } from '@lingui/core'
import { I18nProvider } from '@lingui/react'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { Notifications } from './index'

const post = vi.fn(async (..._args: unknown[]) => ({}))
const navigate = vi.fn()
const openTab = vi.fn((_url: string) => true)

const row = (id: string, read: number) => ({
  id,
  app: 'chat',
  topic: 'message',
  object: id,
  content: `Message ${id}`,
  link: `/chat/${id}`,
  count: 1,
  created: 1,
  read,
})

// Partial mock: the page pulls its layout and primitives from @mochi/web and
// they have to keep rendering, so only the requests, the two ways out of the
// page and the stored "Show all" switch are replaced.
vi.mock('@mochi/web', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@mochi/web')>()
  return {
    ...actual,
    requestHelpers: {
      ...actual.requestHelpers,
      getRaw: vi.fn(async () => ({
        data: [row('unread', 0), row('seen', 5)],
        count: 1,
        total: 1,
      })),
      post: (...args: unknown[]) => post(...args),
    },
    shellNavigateExternal: (url: string) => navigate(url),
    shellOpenExternal: (url: string) => openTab(url),
    useShellStorage: () => [true, vi.fn()],
    usePageTitle: () => {},
  }
})

function mount() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  return render(
    <QueryClientProvider client={queryClient}>
      <I18nProvider i18n={i18n}>
        <Notifications />
      </I18nProvider>
    </QueryClientProvider>
  )
}

describe('Notifications', () => {
  beforeEach(() => {
    post.mockClear()
    navigate.mockClear()
    openTab.mockClear()
  })

  it('marks one notification read from its button and stays on the page', async () => {
    mount()
    await screen.findByText('Message unread')

    await userEvent.click(screen.getByRole('button', { name: 'Mark as read' }))

    expect(post).toHaveBeenCalledTimes(1)
    expect(post.mock.calls[0][0]).toBe('-/read')
    expect(post.mock.calls[0][1]).toBe('id=unread')
    expect(navigate).not.toHaveBeenCalled()
    expect(openTab).not.toHaveBeenCalled()
  })

  it('offers the button on unread rows only', async () => {
    mount()
    await screen.findByText('Message seen')

    expect(
      screen.getAllByRole('button', { name: 'Mark as read' })
    ).toHaveLength(1)
  })

  it('opens the link in a new tab on a middle click and marks the row read', async () => {
    mount()
    const text = await screen.findByText('Message unread')

    fireEvent(
      text.closest('button')!,
      new MouseEvent('auxclick', { bubbles: true, button: 1 })
    )

    expect(openTab).toHaveBeenCalledWith('/chat/unread')
    expect(navigate).not.toHaveBeenCalled()
    await waitFor(() => expect(post).toHaveBeenCalledTimes(1))
    expect(post.mock.calls[0][1]).toBe('id=unread')
  })
})
