import { useState, useMemo, useEffect } from 'react'
import { Link } from '@tanstack/react-router'
import { PageHeader, Main } from '@mochi/common'
import { Button } from '@mochi/common/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@mochi/common/components/ui/dropdown-menu'
import { Label } from '@mochi/common/components/ui/label'
import { Switch } from '@mochi/common/components/ui/switch'
import { cn } from '@mochi/common/lib/utils'
import {
  Bell,
  Check,
  ListChecks,
  Loader2,
  MoreVertical,
  Trash2,
} from 'lucide-react'
import type { Notification as ApiNotification } from '@/api/notifications'
import { useNotificationWebSocket } from '@/hooks/useNotificationWebSocket'
import {
  useNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useClearAllMutation,
} from '@/hooks/useNotifications'

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
      type='button'
      onClick={handleClick}
      className={cn(
        'hover:bg-accent flex w-full items-start gap-3 rounded-lg px-4 py-3 text-left transition-colors',
        isUnread && 'bg-accent/50'
      )}
    >
      {isUnread && (
        <span className='bg-primary mt-1.5 size-2 shrink-0 rounded-full' />
      )}
      <div className={cn('min-w-0 flex-1', !isUnread && 'ml-5')}>
        <p className='text-sm leading-snug'>
          {notification.content}
          {notification.count > 1 && (
            <span className='text-muted-foreground'>
              {' '}
              ({notification.count})
            </span>
          )}
        </p>
        <p className='text-muted-foreground mt-0.5 text-xs'>
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

  const { data, isLoading, isError } = useNotificationsQuery()

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, String(showAll))
  }, [showAll])

  useNotificationWebSocket()
  const markAsReadMutation = useMarkAsReadMutation()
  const markAllAsReadMutation = useMarkAllAsReadMutation()
  const clearAllMutation = useClearAllMutation()

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
    <>
      <PageHeader
        title='Notifications'
        icon={<Bell className='size-4 md:size-5' />}
        actions={
          <div className='flex items-center gap-2'>
            <div className='mr-2 flex items-center gap-2'>
              <Switch
                id='show-all'
                checked={showAll}
                onCheckedChange={setShowAll}
              />
              <Label
                htmlFor='show-all'
                className='text-muted-foreground hidden text-sm md:block'
              >
                Show all
              </Label>
            </div>
            {unreadCount > 0 && (
              <Button
                variant='ghost'
                size='sm'
                onClick={handleMarkAllAsRead}
                disabled={markAllAsReadMutation.isPending}
              >
                {markAllAsReadMutation.isPending ? (
                  <Loader2 className='mr-1.5 size-4 animate-spin' />
                ) : (
                  <Check className='mr-1.5 size-4' />
                )}
                <span className='hidden md:inline'>Mark all read</span>
              </Button>
            )}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant='ghost' size='icon'>
                  <MoreVertical className='size-5' />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align='end'>
                {allNotifications.length > 0 && (
                  <DropdownMenuItem
                    onClick={handleClearAll}
                    disabled={clearAllMutation.isPending}
                  >
                    <Trash2 className='mr-2 size-4' />
                    Clear all
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem asChild>
                  <Link to='/manage'>
                    <ListChecks className='mr-2 size-4' />
                    Manage notifications
                  </Link>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        }
      />
      <Main>
        <div className='mx-auto max-w-2xl'>
          {/* Loading */}
          {isLoading && (
            <div className='flex items-center justify-center py-12'>
              <Loader2 className='text-muted-foreground size-6 animate-spin' />
            </div>
          )}

          {/* Error */}
          {isError && (
            <div className='text-destructive py-12 text-center text-sm'>
              Failed to load notifications
            </div>
          )}

          {/* List */}
          {!isLoading && !isError && (
            <>
              {displayedNotifications.length === 0 ? (
                <div className='py-12 text-center'>
                  <Bell className='text-muted-foreground/40 mx-auto mb-3 size-10' />
                  <p className='text-muted-foreground text-sm'>
                    {showAll ? 'No notifications' : 'No unread notifications'}
                  </p>
                </div>
              ) : (
                <div className='space-y-1'>
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
      </Main>
    </>
  )
}
