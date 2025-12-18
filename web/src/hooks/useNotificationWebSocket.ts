import { useEffect, useRef, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { notificationKeys } from './useNotifications'

interface NotificationEvent {
  type: 'new' | 'read' | 'read_all' | 'clear_all' | 'clear_app' | 'clear_object'
  id?: string
  app?: string
  category?: string
  object?: string
  content?: string
  link?: string
}

const RECONNECT_DELAY = 3000

// Build WebSocket URL for notifications
function getWebSocketUrl(): string {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${window.location.host}/_/websocket?key=notifications`
}

// Hook to connect to notification WebSocket and invalidate queries on events
export function useNotificationWebSocket() {
  const queryClient = useQueryClient()
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const mountedRef = useRef(true)

  const connect = useCallback(() => {
    if (!mountedRef.current) return
    if (wsRef.current?.readyState === WebSocket.OPEN) return

    const ws = new WebSocket(getWebSocketUrl())
    wsRef.current = ws

    ws.onmessage = (event) => {
      try {
        const data: NotificationEvent = JSON.parse(event.data)

        switch (data.type) {
          case 'new':
          case 'read':
          case 'read_all':
          case 'clear_all':
          case 'clear_app':
          case 'clear_object':
            queryClient.invalidateQueries({ queryKey: notificationKeys.list() })
            break
        }
      } catch {
        // Ignore parse errors
      }
    }

    ws.onclose = () => {
      wsRef.current = null
      // Reconnect after delay if still mounted
      if (mountedRef.current) {
        reconnectTimerRef.current = setTimeout(connect, RECONNECT_DELAY)
      }
    }

    ws.onerror = () => {
      // Error will trigger onclose, which handles reconnection
    }
  }, [queryClient])

  useEffect(() => {
    mountedRef.current = true
    connect()

    return () => {
      mountedRef.current = false
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current)
      }
      if (wsRef.current) {
        wsRef.current.close()
        wsRef.current = null
      }
    }
  }, [connect])
}

export default useNotificationWebSocket
