// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useAuthStore } from '@mochi/web'
import { act, renderHook, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { notificationsApi } from '@/api/notifications'
import {
  useMarkAllAsReadMutation,
  useMarkAsReadMutation,
  useNotificationsLiveRefresh,
  useNotificationsQuery,
} from './useNotifications'

vi.mock('@/api/notifications', () => ({
  notificationsApi: {
    list: vi.fn(),
    markAsRead: vi.fn(),
    markAllAsRead: vi.fn(),
  },
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

// The page's notifications socket, captured so a test can open it and deliver
// frames to it.
class FrameSocket {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSING = 2
  static CLOSED = 3
  static sockets: FrameSocket[] = []
  readyState = 0
  onopen: (() => void) | null = null
  onmessage: ((event: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  constructor(
    public url: string,
    public protocols?: string | string[]
  ) {
    FrameSocket.sockets.push(this)
  }
  open() {
    this.readyState = 1
    this.onopen?.()
  }
  send(frame: object) {
    this.onmessage?.({ data: JSON.stringify(frame) })
  }
  drop() {
    this.readyState = 3
    this.onclose?.()
  }
  close() {
    this.readyState = 3
  }
}

const row = (id: string, created: number, read = 0) => ({
  id,
  app: 'chat',
  topic: 'message',
  object: 'o1',
  content: `Message ${id}`,
  link: `/chat/${id}`,
  sender: 'sender-entity',
  count: 1,
  created,
  read,
})

type Row = ReturnType<typeof row>

// What the server lists, as the tests change it: the list a fetch answers.
let server: Row[] = []

beforeEach(() => {
  listeners = []
  server = [row('a', 10)]
  FrameSocket.sockets = []
  vi.stubGlobal('WebSocket', FrameSocket)
  vi.mocked(notificationsApi.list).mockReset()
  vi.mocked(notificationsApi.list).mockImplementation(async () => ({
    data: server.map((entry) => ({ ...entry })),
  }))
  useAuthStore.setState({ isInitialized: true, token: 'page-token' })
})

afterEach(() => {
  useAuthStore.setState({ isInitialized: false, token: '' })
  vi.unstubAllGlobals()
})

function mount() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  const view = renderHook(
    () => {
      useNotificationsLiveRefresh()
      return {
        list: useNotificationsQuery(),
        read: useMarkAsReadMutation(),
        readAll: useMarkAllAsReadMutation(),
      }
    },
    {
      wrapper: ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={queryClient}>
          {children}
        </QueryClientProvider>
      ),
    }
  )
  const held = () => view.result.current.list.data?.data ?? []
  const fetches = () => vi.mocked(notificationsApi.list).mock.calls.length
  const socket = () => FrameSocket.sockets[FrameSocket.sockets.length - 1]
  return { queryClient, view, held, fetches, socket }
}

// Mounted, the list loaded and the socket open, with the open's own fetch of
// the list landed.
async function live() {
  const page = mount()
  await waitFor(() => expect(page.held()).toEqual(server))
  await waitFor(() => expect(FrameSocket.sockets).toHaveLength(1))
  const loaded = page.fetches()
  act(() => page.socket().open())
  await waitFor(() => expect(page.fetches()).toBe(loaded + 1))
  await waitFor(() =>
    expect(
      page.queryClient.getQueryState(['notifications', 'list'])?.fetchStatus
    ).toBe('idle')
  )
  return page
}

// The page used to fetch its whole list again for every event the bell passed
// down, as the shell forwards only the event's type. It now holds its own
// socket, with its own token, and applies the frames to the list it holds.
describe('useNotificationsLiveRefresh', () => {
  it('opens its own notifications socket with the page’s token', async () => {
    const page = mount()
    await waitFor(() => expect(FrameSocket.sockets).toHaveLength(1))
    expect(page.socket().url).toContain('/_/websocket?key=notifications')
    expect(page.socket().protocols).toEqual(['mochi.token.page-token'])
  })

  it('opens none before the page has its token', async () => {
    useAuthStore.setState({ isInitialized: true, token: '' })
    const page = mount()
    await waitFor(() => expect(page.held()).toHaveLength(1))
    expect(FrameSocket.sockets).toHaveLength(0)
  })

  it('closes its socket once the page is gone', async () => {
    const page = await live()
    const socket = page.socket()
    page.view.unmount()
    expect(socket.onmessage).toBeNull()
    expect(socket.readyState).toBe(FrameSocket.CLOSED)
  })

  it('applies a new notification, a read and a read of every row, fetching nothing', async () => {
    const page = await live()
    const before = page.fetches()

    server = [row('a', 10), row('b', 20)]
    act(() => page.socket().send({ type: 'new', web: true, ...row('b', 20) }))
    await waitFor(() =>
      expect(page.held().map((n) => n.id)).toEqual(['a', 'b'])
    )
    expect(page.held()).toEqual(server)

    act(() => page.socket().send({ type: 'read', id: 'a' }))
    await waitFor(() => expect(page.held()[0].read).toBeGreaterThan(0))
    act(() => page.socket().send({ type: 'read_all' }))
    await waitFor(() => expect(page.held().every((n) => n.read > 0)).toBe(true))
    expect(page.fetches()).toBe(before)
  })

  it('replaces a row sent again, and drops one the browser surface does not list, as a fetch would', async () => {
    server = [row('a', 10), row('b', 20)]
    const page = await live()
    const before = page.fetches()

    server = [row('b', 20), { ...row('a', 30), count: 2 }]
    act(() =>
      page.socket().send({ type: 'new', web: true, ...row('a', 30), count: 2 })
    )
    await waitFor(() => expect(page.held()).toEqual(server))

    server = [{ ...row('a', 30), count: 2 }]
    act(() => page.socket().send({ type: 'new', web: false, ...row('b', 40) }))
    await waitFor(() => expect(page.held()).toEqual(server))
    expect(page.fetches()).toBe(before)
  })

  it('fetches the list for a frame it cannot apply, and on a reconnect', async () => {
    const page = await live()
    const before = page.fetches()

    server = []
    act(() => page.socket().send({ type: 'clear_all' }))
    await waitFor(() => expect(page.fetches()).toBe(before + 1))
    await waitFor(() => expect(page.held()).toEqual([]))

    act(() => page.socket().send({ type: 'categories' }))
    await waitFor(() => expect(page.fetches()).toBe(before + 2))

    // A frame from a notifications app too old to say whether the surface
    // lists the row.
    act(() => page.socket().send({ type: 'new', ...row('c', 30) }))
    await waitFor(() => expect(page.fetches()).toBe(before + 3))

    act(() => page.socket().drop())
    await waitFor(() => expect(FrameSocket.sockets).toHaveLength(2), {
      timeout: 3000,
    })
    act(() => page.socket().open())
    await waitFor(() => expect(page.fetches()).toBe(before + 4))
  })

  it('fetches nothing for a clear that changed no row, or a frame of another kind', async () => {
    const page = await live()
    const before = page.fetches()
    act(() =>
      page
        .socket()
        .send({ type: 'clear_object', app: 'chat', object: 'o1', changed: 0 })
    )
    act(() => page.socket().send({ type: 'ping' }))
    server = [row('a', 10), row('b', 20)]
    act(() => page.socket().send({ type: 'new', web: true, ...row('b', 20) }))
    await waitFor(() => expect(page.held()).toEqual(server))
    expect(page.fetches()).toBe(before)
  })

  it('leaves the list alone when the bell passes on a notification event', async () => {
    const page = await live()
    const before = page.fetches()
    for (const listener of listeners) listener({ type: 'notification-update' })
    await new Promise((resolve) => setTimeout(resolve, 20))
    expect(page.fetches()).toBe(before)
  })
})

// A row goes read on the click, its frame changes nothing, and nothing is
// fetched; a refused read fetches the list, the server's word on it.
describe('marking read', () => {
  let refuse: (error: unknown) => void
  let accept: () => void
  beforeEach(() => {
    server = [row('n1', 1), row('n2', 2)]
    const waiting = () =>
      new Promise<void>((resolve, reject) => {
        accept = resolve
        refuse = reject
      })
    vi.mocked(notificationsApi.markAsRead).mockImplementation(waiting)
    vi.mocked(notificationsApi.markAllAsRead).mockImplementation(waiting)
  })

  const readIds = (page: ReturnType<typeof mount>) =>
    page
      .held()
      .filter((n) => n.read !== 0)
      .map((n) => n.id)

  it('marks one read at once, and fetches nothing when the server agrees', async () => {
    const page = await live()
    const before = page.fetches()
    act(() => page.view.result.current.read.mutate('n1'))
    await waitFor(() => expect(readIds(page)).toEqual(['n1']))

    // The server marks it read and its frame comes back over the socket.
    server = [{ ...row('n1', 1), read: 9 }, row('n2', 2)]
    act(() => page.socket().send({ type: 'read', id: 'n1' }))
    await act(async () => accept())
    await waitFor(() =>
      expect(page.view.result.current.read.isSuccess).toBe(true)
    )
    expect(readIds(page)).toEqual(['n1'])
    expect(page.fetches()).toBe(before)
  })

  it('marks one read at once and unread again when refused', async () => {
    const page = await live()
    act(() => page.view.result.current.read.mutate('n1'))
    await waitFor(() => expect(readIds(page)).toEqual(['n1']))

    act(() => refuse(new Error('refused')))
    await waitFor(() =>
      expect(page.view.result.current.read.isError).toBe(true)
    )
    await waitFor(() => expect(readIds(page)).toEqual([]))
  })

  it('keeps a notification that arrived meanwhile when a read is refused', async () => {
    const page = await live()
    act(() => page.view.result.current.read.mutate('n1'))
    await waitFor(() => expect(readIds(page)).toEqual(['n1']))

    server = [row('n1', 1), row('n2', 2), row('n3', 3)]
    act(() => page.socket().send({ type: 'new', web: true, ...row('n3', 3) }))
    await waitFor(() => expect(page.held()).toHaveLength(3))

    act(() => refuse(new Error('refused')))
    await waitFor(() =>
      expect(page.view.result.current.read.isError).toBe(true)
    )
    await waitFor(() => expect(page.held()).toEqual(server))
  })

  it('marks all read at once, and fetches nothing when the server agrees', async () => {
    const page = await live()
    const before = page.fetches()
    act(() => page.view.result.current.readAll.mutate())
    await waitFor(() => expect(readIds(page)).toEqual(['n1', 'n2']))

    act(() => page.socket().send({ type: 'read_all' }))
    await act(async () => accept())
    await waitFor(() =>
      expect(page.view.result.current.readAll.isSuccess).toBe(true)
    )
    expect(readIds(page)).toEqual(['n1', 'n2'])
    expect(page.fetches()).toBe(before)
  })

  it('marks all read at once and unread again when refused', async () => {
    const page = await live()
    act(() => page.view.result.current.readAll.mutate())
    await waitFor(() => expect(readIds(page)).toEqual(['n1', 'n2']))

    act(() => refuse(new Error('refused')))
    await waitFor(() =>
      expect(page.view.result.current.readAll.isError).toBe(true)
    )
    await waitFor(() => expect(readIds(page)).toEqual([]))
  })
})
