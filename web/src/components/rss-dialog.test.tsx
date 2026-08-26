// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

/* eslint-disable lingui/no-unlocalized-strings */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { I18nProvider } from '@lingui/react'
import { i18n } from '@lingui/core'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const clipboard = vi.fn<(text: string) => Promise<boolean>>()
const errorToast = vi.fn()

// Partial mock: the dialog pulls two dozen real primitives from @mochi/web and
// they have to keep rendering, so only the clipboard bridge, the toaster and
// the one request helper the list query uses are replaced.
vi.mock('@mochi/web', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@mochi/web')>()
  return {
    ...actual,
    shellClipboardWrite: (text: string) => clipboard(text),
    toast: Object.assign(vi.fn(), {
      success: vi.fn(),
      error: errorToast,
      warning: vi.fn(),
      info: vi.fn(),
      message: vi.fn(),
      dismiss: vi.fn(),
    }),
    requestHelpers: {
      ...actual.requestHelpers,
      get: vi.fn(async () => [
        { id: 'feed-1', name: 'Everything', token: 'tok-1', created: 1, enabled: 1 },
      ]),
      post: vi.fn(async () => ({})),
    },
  }
})

const { RssDialog } = await import('./rss-dialog')

function renderDialog() {
  const onOpenChange = vi.fn()
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  render(
    <QueryClientProvider client={client}>
      <I18nProvider i18n={i18n}>
        <RssDialog open onOpenChange={onOpenChange} />
      </I18nProvider>
    </QueryClientProvider>
  )
  return { onOpenChange }
}

beforeEach(() => {
  clipboard.mockReset()
  errorToast.mockReset()
})

describe('RssDialog', () => {
  it('reports a refused clipboard write instead of doing nothing', async () => {
    // The shell iframe is sandboxed without allow-same-origin, so a clipboard
    // write is refused far more often here than in the top window. Silence
    // there reads as "copied" and the user pastes the previous entry.
    clipboard.mockResolvedValue(false)
    renderDialog()

    const copy = await screen.findByRole('button', { name: 'Copy' })
    await userEvent.click(copy)

    await waitFor(() => expect(errorToast).toHaveBeenCalledWith('Failed to copy'))
  })

  it('stays silent when the clipboard write succeeds', async () => {
    clipboard.mockResolvedValue(true)
    renderDialog()

    await userEvent.click(await screen.findByRole('button', { name: 'Copy' }))

    await waitFor(() => expect(clipboard).toHaveBeenCalled())
    expect(errorToast).not.toHaveBeenCalled()
  })

  it('returns Cancel in the create view to the list, without closing the dialog', async () => {
    clipboard.mockResolvedValue(true)
    const { onOpenChange } = renderDialog()

    await userEvent.click(await screen.findByRole('button', { name: 'Create feed' }))
    expect(await screen.findByLabelText('Feed name')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))

    // Back on the list, and the dialog was never asked to close.
    expect(await screen.findByRole('button', { name: 'Create feed' })).toBeInTheDocument()
    expect(screen.queryByLabelText('Feed name')).not.toBeInTheDocument()
    expect(onOpenChange).not.toHaveBeenCalled()
  })

  it('clears the typed name when Cancel returns to the list', async () => {
    // The reset the dialog already had runs off the `open` prop, so returning
    // to the list without closing skips it and the next visit to the create
    // view would still hold the abandoned name.
    clipboard.mockResolvedValue(true)
    renderDialog()

    await userEvent.click(await screen.findByRole('button', { name: 'Create feed' }))
    await userEvent.type(await screen.findByLabelText('Feed name'), 'Abandoned')
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))

    await userEvent.click(await screen.findByRole('button', { name: 'Create feed' }))
    expect(await screen.findByLabelText('Feed name')).toHaveValue('')
  })
})
