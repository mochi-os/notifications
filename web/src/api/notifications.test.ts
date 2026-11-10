// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { notificationsApi } from './notifications'

// The server's own bodies, served through the real request helper: what these
// calls return depends on how that helper opens the data envelope.
const bodies: Record<string, unknown> = {
  '-/categories/list': {
    data: [{ id: '1', label: 'Normal', default: 1, destinations: [] }],
  },
  '-/topics/lookup': {
    data: {
      app: 'chat',
      topic: 'message',
      object: 'abc',
      label: 'Messages',
      category: '1',
    },
  },
}

describe('notificationsApi', () => {
  beforeEach(() => {
    // The server's answer to the path the request reached, under the app.
    const serve = async (url: string) =>
      new Response(
        JSON.stringify(bodies[url.split('?')[0].replace(/^.*?\/-\//, '-/')])
      )
    vi.stubGlobal('fetch', serve)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('returns the categories the server lists', async () => {
    const categories = await notificationsApi.listCategories()
    expect(categories.map((category) => category.id)).toEqual(['1'])
  })

  it('returns the topic row the server finds', async () => {
    const row = await notificationsApi.lookupTopic('chat', 'message', 'abc')
    expect(row).toMatchObject({ label: 'Messages', category: '1' })
  })

  it('returns no topic when the server has none', async () => {
    bodies['-/topics/lookup'] = { data: null }
    expect(
      await notificationsApi.lookupTopic('chat', 'message', 'abc')
    ).toBeNull()
  })
})
