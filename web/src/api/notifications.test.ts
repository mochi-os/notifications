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
