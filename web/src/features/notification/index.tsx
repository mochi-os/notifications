import { useState, useMemo } from 'react'
import {
  Bell,
  BellRing,
  Check,
  MessageSquare,
  UserPlus,
  Users,
  Loader2,
} from 'lucide-react'
import { cn } from '@mochi/common/lib/utils'
import { Button } from '@mochi/common/components/ui/button'
import { Badge } from '@mochi/common/components/ui/badge'
import { TopBar } from '@mochi/common/components/layout/top-bar'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@mochi/common/components/ui/tabs'
import { ScrollArea } from '@mochi/common/components/ui/scroll-area'
import {
  Card,
  CardContent,
} from '@mochi/common/components/ui/card'
import {
  useNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
} from '@/hooks/useNotifications'
import type { Notification as ApiNotification } from '@/api/notifications'

function getNotificationIcon(app: string, category: string) {
  if (app === 'friends') {
    if (category === 'accept') return Users
    if (category === 'invite') return UserPlus
  }
  if (app === 'chat') return MessageSquare
  return Bell
}

function getNotificationColor(app: string, category: string) {
  if (app === 'friends') {
    if (category === 'accept') return 'bg-green-500'
    if (category === 'invite') return 'bg-blue-500'
  }
  if (app === 'chat') return 'bg-purple-500'
  return 'bg-gray-500'
}

function formatTimestamp(timestamp: number): string {
  const now = Date.now() / 1000
  const diff = now - timestamp

  if (diff < 60) return 'Just now'
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`

  const date = new Date(timestamp * 1000)
  return date.toLocaleDateString()
}

function NotificationItem({
  notification,
  onMarkAsRead,
}: {
  notification: ApiNotification
  onMarkAsRead: (id: string) => void
}) {
  const Icon = getNotificationIcon(notification.app, notification.category)
  const iconColor = getNotificationColor(notification.app, notification.category)
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
    <div
      onClick={handleClick}
      className={cn(
        'group relative flex gap-3 rounded-lg p-4 transition-colors hover:bg-accent cursor-pointer',
        isUnread && 'bg-accent/50'
      )}
    >
      <div className='relative shrink-0'>
        <div
          className={cn(
            'flex size-10 items-center justify-center rounded-full',
            iconColor
          )}
        >
          <Icon className='size-5 text-white' />
        </div>
      </div>
      <div className='flex-1 space-y-1'>
        <div className='flex items-start justify-between gap-2'>
          <div className='flex-1'>
            <p className='text-sm leading-tight'>
              {notification.content}
              {notification.count > 1 && (
                <span className='text-muted-foreground ml-1'>
                  ({notification.count})
                </span>
              )}
            </p>
          </div>
          {isUnread && (
            <div className='size-2 shrink-0 rounded-full bg-primary mt-1.5' />
          )}
        </div>
        <p className='text-xs text-muted-foreground'>
          {formatTimestamp(notification.created)}
        </p>
      </div>
    </div>
  )
}

export function Notifications() {
  const [activeTab, setActiveTab] = useState('all')
  const { data: notifications, isLoading, isError } = useNotificationsQuery()
  const markAsReadMutation = useMarkAsReadMutation()
  const markAllAsReadMutation = useMarkAllAsReadMutation()

  const allNotifications = useMemo(() => notifications ?? [], [notifications])
  const unreadNotifications = useMemo(
    () => allNotifications.filter((n) => n.read === 0),
    [allNotifications]
  )
  const unreadCount = unreadNotifications.length

  const handleMarkAsRead = (id: string) => {
    markAsReadMutation.mutate(id)
  }

  const handleMarkAllAsRead = () => {
    markAllAsReadMutation.mutate()
  }

  return (
    <>
      <TopBar title="Notifications" />

      <main className='mx-auto max-w-7xl px-4 py-6 sm:px-6'>
        {/* Page Header */}
        <div className='mb-6 flex items-center justify-between'>
          <div>
            <h1 className='text-2xl font-bold tracking-tight'>Notifications</h1>
            <p className='text-muted-foreground'>
              Stay updated with your latest activity
            </p>
          </div>
          {unreadCount > 0 && (
            <Button
              variant='outline'
              size='sm'
              onClick={handleMarkAllAsRead}
              disabled={markAllAsReadMutation.isPending}
              className='text-sm'
            >
              {markAllAsReadMutation.isPending ? (
                <Loader2 className='mr-2 h-4 w-4 animate-spin' />
              ) : (
                <Check className='mr-2 h-4 w-4' />
              )}
              Mark all as read
            </Button>
          )}
        </div>

        {/* Loading State */}
        {isLoading && (
          <div className='flex items-center justify-center py-12'>
            <Loader2 className='h-8 w-8 animate-spin text-muted-foreground' />
          </div>
        )}

        {/* Error State */}
        {isError && (
          <div className='flex flex-col items-center justify-center py-12 text-center'>
            <p className='text-destructive font-medium'>Failed to load notifications</p>
          </div>
        )}

        {/* Tabs */}
        {!isLoading && !isError && (
          <Tabs value={activeTab} onValueChange={setActiveTab}>
            <TabsList className='grid w-full max-w-md grid-cols-2'>
              <TabsTrigger value='all' className='relative'>
                All
                {allNotifications.length > 0 && (
                  <Badge
                    variant='secondary'
                    className='ml-1.5 flex items-center justify-center gap-0.5 rounded-full px-1 py-0 text-[10px]'
                  >
                    <Bell className='h-3 w-3' />
                    {allNotifications.length}
                  </Badge>
                )}
              </TabsTrigger>
              <TabsTrigger value='unread' className='relative'>
                Unread
                {unreadCount > 0 && (
                  <Badge
                    variant='default'
                    className='ml-1.5 flex items-center justify-center gap-0.5 rounded-full px-1 py-0 text-[10px]'
                  >
                    <BellRing className='h-3 w-3' />
                    {unreadCount}
                  </Badge>
                )}
              </TabsTrigger>
            </TabsList>

            {/* Notifications List */}
            <TabsContent value='all' className='mt-6'>
              <Card>
                <CardContent className='p-0'>
                  <ScrollArea className='h-[calc(100vh-310px)]'>
                    <div className='p-4'>
                      {allNotifications.length === 0 ? (
                        <div className='flex flex-col items-center justify-center py-12 text-center'>
                          <Bell className='mb-4 size-12 text-muted-foreground/50' />
                          <p className='text-sm font-medium text-muted-foreground'>
                            No notifications
                          </p>
                          <p className='mt-1 text-xs text-muted-foreground/80'>
                            You have no notifications yet
                          </p>
                        </div>
                      ) : (
                        <div className='space-y-1'>
                          {allNotifications.map((notification) => (
                            <NotificationItem
                              key={notification.id}
                              notification={notification}
                              onMarkAsRead={handleMarkAsRead}
                            />
                          ))}
                        </div>
                      )}
                    </div>
                  </ScrollArea>
                </CardContent>
              </Card>
            </TabsContent>
            <TabsContent value='unread' className='mt-6'>
              <Card>
                <CardContent className='p-0'>
                  <ScrollArea className='h-[calc(100vh-310px)]'>
                    <div className='p-4'>
                      {unreadNotifications.length === 0 ? (
                        <div className='flex flex-col items-center justify-center py-12 text-center'>
                          <Bell className='mb-4 size-12 text-muted-foreground/50' />
                          <p className='text-sm font-medium text-muted-foreground'>
                            All caught up!
                          </p>
                          <p className='mt-1 text-xs text-muted-foreground/80'>
                            You have no unread notifications
                          </p>
                        </div>
                      ) : (
                        <div className='space-y-1'>
                          {unreadNotifications.map((notification) => (
                            <NotificationItem
                              key={notification.id}
                              notification={notification}
                              onMarkAsRead={handleMarkAsRead}
                            />
                          ))}
                        </div>
                      )}
                    </div>
                  </ScrollArea>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        )}
      </main>
    </>
  )
}
