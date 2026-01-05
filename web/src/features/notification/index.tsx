import { useState, useMemo, useEffect } from 'react'
import { Bell, Check, Copy, Loader2, MoreVertical, Rss, Trash2 } from 'lucide-react'
import { cn } from '@mochi/common/lib/utils'
import { toast, usePush } from '@mochi/common'
import { Button } from '@mochi/common/components/ui/button'
import { Switch } from '@mochi/common/components/ui/switch'
import { Label } from '@mochi/common/components/ui/label'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@mochi/common/components/ui/dropdown-menu'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@mochi/common/components/ui/dialog'
import {
  useNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useClearAllMutation,
  useRssTokenMutation,
} from '@/hooks/useNotifications'
import { useNotificationWebSocket } from '@/hooks/useNotificationWebSocket'
import type { Notification as ApiNotification } from '@/api/notifications'

const STORAGE_KEY = 'notifications-show-all'

function formatTimestamp(timestamp: number): string {
  const now = Date.now() / 1000
  const diff = now - timestamp

  if (diff < 60) return 'Just now'
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`

  const date = new Date(timestamp * 1000)
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
}

function NotificationItem({
  notification,
  onMarkAsRead,
}: {
  notification: ApiNotification
  onMarkAsRead: (id: string) => void
}) {
  const isUnread = notification.read === 0

  const handleClick = () => {
    if (isUnread) {
      onMarkAsRead(notification.id)
    }
    if (notification.link) {
      window.location.href = notification.link
    }
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      className={cn(
        'flex w-full items-start gap-3 rounded-lg px-4 py-3 text-left transition-colors hover:bg-accent',
        isUnread && 'bg-accent/50'
      )}
    >
      {isUnread && (
        <span className="mt-1.5 size-2 shrink-0 rounded-full bg-primary" />
      )}
      <div className={cn('flex-1 min-w-0', !isUnread && 'ml-5')}>
        <p className="text-sm leading-snug">
          {notification.content}
          {notification.count > 1 && (
            <span className="text-muted-foreground"> ({notification.count})</span>
          )}
        </p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {formatTimestamp(notification.created)}
        </p>
      </div>
    </button>
  )
}

export function Notifications() {
  const [showAll, setShowAll] = useState(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem(STORAGE_KEY) === 'true'
    }
    return false
  })
  const [rssOpen, setRssOpen] = useState(false)
  const [rssUrl, setRssUrl] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)

  const { data, isLoading, isError } = useNotificationsQuery()

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, String(showAll))
  }, [showAll])

  useNotificationWebSocket()
  const markAsReadMutation = useMarkAsReadMutation()
  const markAllAsReadMutation = useMarkAllAsReadMutation()
  const clearAllMutation = useClearAllMutation()
  const rssTokenMutation = useRssTokenMutation()
  const push = usePush()

  const handleTogglePush = () => {
    if (push.subscribed) {
      push.unsubscribe()
      toast.success('Push notifications disabled')
    } else {
      push.subscribe()
      toast.success('Push notifications enabled')
    }
  }

  const handleOpenRss = () => {
    setRssOpen(true)
    if (!rssUrl) {
      rssTokenMutation.mutate(undefined, {
        onSuccess: (token) => {
          setRssUrl(`${window.location.origin}/notifications/rss?token=${token}`)
        },
      })
    }
  }

  const handleCopyRss = async () => {
    if (rssUrl) {
      await navigator.clipboard.writeText(rssUrl)
      setCopied(true)
      toast.success('Copied to clipboard')
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const allNotifications = useMemo(() => data?.data ?? [], [data])
  const unreadCount = useMemo(
    () => allNotifications.filter((n) => n.read === 0).length,
    [allNotifications]
  )

  const displayedNotifications = showAll
    ? allNotifications
    : allNotifications.filter((n) => n.read === 0)

  const handleMarkAsRead = (id: string) => {
    markAsReadMutation.mutate(id)
  }

  const handleMarkAllAsRead = () => {
    markAllAsReadMutation.mutate()
  }

  const handleClearAll = () => {
    clearAllMutation.mutate()
  }

  return (
    <main className="px-4 py-6">
      {/* Header */}
      <div className="mb-6 flex items-start">
        <div className="flex-1" />
        <div className="flex flex-col items-center gap-2">
          <h1 className="text-2xl font-bold tracking-tight">Notifications</h1>
          <div className="flex items-center gap-2">
            <Switch
              id="show-all"
              checked={showAll}
              onCheckedChange={setShowAll}
            />
            <Label htmlFor="show-all" className="text-sm text-muted-foreground">
              Show all
            </Label>
          </div>
        </div>
        <div className="flex flex-1 items-center justify-end gap-2">
          {unreadCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleMarkAllAsRead}
              disabled={markAllAsReadMutation.isPending}
            >
              {markAllAsReadMutation.isPending ? (
                <Loader2 className="mr-1.5 size-4 animate-spin" />
              ) : (
                <Check className="mr-1.5 size-4" />
              )}
              Mark all read
            </Button>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon">
                <MoreVertical className="size-5" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {allNotifications.length > 0 && (
                <DropdownMenuItem
                  onClick={handleClearAll}
                  disabled={clearAllMutation.isPending}
                >
                  <Trash2 className="mr-2 size-4" />
                  Clear all
                </DropdownMenuItem>
              )}
              {push.supported && (
                <DropdownMenuItem onSelect={(e) => e.preventDefault()}>
                  <Bell className="mr-2 size-4" />
                  Browser notifications
                  <Switch
                    className="ml-auto cursor-pointer"
                    checked={push.subscribed}
                    onCheckedChange={handleTogglePush}
                    disabled={push.isSubscribing || push.isUnsubscribing}
                  />
                </DropdownMenuItem>
              )}
              {data?.rss && (
                <DropdownMenuItem onClick={handleOpenRss}>
                  <Rss className="mr-2 size-4" />
                  RSS feed
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {/* Content */}
      <div className="mx-auto max-w-2xl">
        {/* Loading */}
        {isLoading && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        )}

        {/* Error */}
        {isError && (
          <div className="py-12 text-center text-sm text-destructive">
            Failed to load notifications
          </div>
        )}

        {/* List */}
        {!isLoading && !isError && (
          <>
            {displayedNotifications.length === 0 ? (
              <div className="py-12 text-center">
                <Bell className="mx-auto mb-3 size-10 text-muted-foreground/40" />
                <p className="text-sm text-muted-foreground">
                  {showAll ? 'No notifications' : 'No unread notifications'}
                </p>
              </div>
            ) : (
              <div className="space-y-1">
                {displayedNotifications.map((notification) => (
                  <NotificationItem
                    key={notification.id}
                    notification={notification}
                    onMarkAsRead={handleMarkAsRead}
                  />
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {/* RSS Dialog */}
      <Dialog open={rssOpen} onOpenChange={setRssOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>RSS Feed</DialogTitle>
          </DialogHeader>
          {rssTokenMutation.isPending ? (
            <div className="flex items-center justify-center py-4">
              <Loader2 className="size-6 animate-spin text-muted-foreground" />
            </div>
          ) : rssUrl ? (
            <div className="flex items-center gap-2 rounded-md bg-muted p-3 font-mono text-sm">
              <code className="flex-1 break-all">{rssUrl}</code>
              <Button variant="ghost" size="sm" onClick={handleCopyRss}>
                {copied ? (
                  <Check className="size-4" />
                ) : (
                  <Copy className="size-4" />
                )}
              </Button>
            </div>
          ) : (
            <p className="text-sm text-destructive">Failed to generate URL</p>
          )}
        </DialogContent>
      </Dialog>
    </main>
  )
}
