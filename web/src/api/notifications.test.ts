// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import apiClient from '@mochi/web/lib/api-client'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { notificationsApi } from './notifications'

// The server's own bodies, served through the real request helper: what these
// calls return depends on how that helper opens the data envelope.
const bodies: Record<string, unknown> = {
  '-/list': {
    data: [
      {
        id: 'n1',
        app: 'chat',
        topic: 'message',
        object: 'o1',
        content: 'Hello',
        link: '/chat/o1',
        count: 2,
        created: 1,
        read: 0,
      },
    ],
    count: 1,
    total: 2,
  },
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

const original = apiClient.defaults.adapter

describe('notificationsApi', () => {
  beforeEach(() => {
    const serve = async (config: { url?: string }) => ({
      data: bodies[(config.url ?? '').split('?')[0]],
      status: 200,
      statusText: 'OK',
      headers: {},
      config,
    })
    apiClient.defaults.adapter = serve as unknown as typeof original
  })

  afterEach(() => {
    apiClient.defaults.adapter = original
  })

  // The page applies the socket's frames to the rows it holds, and no frame
  // says how the badge counts beside them change: kept, they would go stale.
  it('holds the rows the server lists and nothing beside them', async () => {
    const list = await notificationsApi.list()
    expect(Object.keys(list)).toEqual(['data'])
    expect(list.data.map((row) => row.id)).toEqual(['n1'])
  })

  it('holds no rows for a list the server sends none of', async () => {
    const saved = bodies['-/list']
    bodies['-/list'] = { data: null }
    expect(await notificationsApi.list()).toEqual({ data: [] })
    bodies['-/list'] = saved
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
