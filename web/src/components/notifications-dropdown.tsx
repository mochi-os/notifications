import { useState } from 'react'
import { Bell, Heart, MessageSquare, UserPlus } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Separator } from '@/components/ui/separator'
import { APP_ROUTES } from '@/config/app-routes'

interface Notification {
  id: string
  type: 'comment' | 'like' | 'follow' | 'mention' | 'invitation'
  read: boolean
  avatar?: string
  name: string
  message: string
  timestamp: string
  actionButtons?: {
    primary: string
    secondary?: string
  }
  metadata?: {
    project?: string
    comment?: string
  }
}


function getNotificationIcon(type: Notification['type']) {
  switch (type) {
    case 'comment':
      return MessageSquare
    case 'like':
      return Heart
    case 'follow':
      return UserPlus
    case 'invitation':
      return UserPlus
    default:
      return Bell
  }
}

function getNotificationColor(type: Notification['type']) {
  switch (type) {
    case 'comment':
      return 'bg-purple-500'
    case 'like':
      return 'bg-red-500'
    case 'follow':
      return 'bg-green-500'
    case 'invitation':
      return 'bg-blue-500'
    default:
      return 'bg-gray-500'
  }
}

function NotificationItem({ notification }: { notification: Notification }) {
  const Icon = getNotificationIcon(notification.type)
  const iconColor = getNotificationColor(notification.type)

  return (
    <div
      className={cn(
        'group relative flex gap-3 rounded-lg p-3 transition-colors hover:bg-accent',
        !notification.read && 'bg-accent/50'
      )}
    >
      <div className='relative shrink-0'>
        <Avatar className='size-10'>
          <AvatarImage src={notification.avatar} alt={notification.name} />
          <AvatarFallback className='text-xs'>
            {notification.name
              .split(' ')
              .map((n) => n[0])
              .join('')
              .toUpperCase()
              .slice(0, 2)}
          </AvatarFallback>
        </Avatar>
        <div
          className={cn(
            'absolute -bottom-0.5 -right-0.5 flex size-5 items-center justify-center rounded border-2 border-background',
            iconColor
          )}
        >
          <Icon className='size-3 text-white' />
        </div>
      </div>
      <div className='flex-1 space-y-1.5'>
        <div className='flex items-start justify-between gap-2'>
          <div className='flex-1 space-y-0.5'>
            <p className='text-sm leading-tight'>
              <span className='font-medium'>{notification.name}</span>{' '}
              {notification.message}
            </p>
            {notification.metadata?.project && (
              <p className='text-xs font-medium text-muted-foreground'>
                {notification.metadata.project}
              </p>
            )}
            {notification.metadata?.comment && (
              <p className='text-xs text-muted-foreground line-clamp-2'>
                {notification.metadata.comment}
              </p>
            )}
          </div>
          {!notification.read && (
            <div className='size-2 shrink-0 rounded-full bg-primary' />
          )}
        </div>

        {notification.actionButtons && (
          <div className='flex gap-2 pt-1'>
            {notification.actionButtons.secondary && (
              <Button
                variant='outline'
                size='sm'
                className='h-7 text-xs'
                onClick={(e) => {
                  e.stopPropagation()
                }}
              >
                {notification.actionButtons.secondary}
              </Button>
            )}
            <Button
              size='sm'
              className='h-7 text-xs'
              onClick={(e) => {
                e.stopPropagation()
              }}
            >
              {notification.actionButtons.primary}
            </Button>
          </div>
        )}

        <p className='text-xs text-muted-foreground'>{notification.timestamp}</p>
      </div>
    </div>
  )
}

export function NotificationsDropdown() {
  const [open, setOpen] = useState(false)
  const [activeTab, setActiveTab] = useState('all')
  const allNotifications: Notification[] = []
  const unreadNotifications: Notification[] = []
  const unreadCount = unreadNotifications.length

  const handleMarkAllAsRead = () => {
    // In a real app, this would update the notifications state
    console.log('Mark all as read')
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant='ghost'
          size='icon'
          className='relative'
          aria-label='Notifications'
        >
          <Bell className='size-5' />
          {unreadCount > 0 && (
            <span className='absolute -right-1 -top-1 flex size-5 items-center justify-center rounded-full bg-destructive text-[10px] font-medium text-destructive-foreground'>
              {unreadCount > 9 ? '9+' : unreadCount}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent
        align='end'
        sideOffset={8}
        className='w-[400px] p-0 sm:w-[420px]'
      >
        <div className='flex flex-col'>
          {/* Header */}
          <div className='flex items-center justify-between border-b px-4 py-3'>
            <h2 className='text-lg font-semibold'>Notifications</h2>
            <div className='flex items-center gap-2'>
              {unreadCount > 0 && (
                <button
                  onClick={handleMarkAllAsRead}
                  className='text-xs text-muted-foreground hover:text-foreground transition-colors'
                >
                  Mark all as read
                </button>
              )}
            </div>
          </div>

          {/* Tabs */}
          <Tabs value={activeTab} onValueChange={setActiveTab}>
            <div className='border-b px-4 pt-3'>
              <TabsList className='grid w-full grid-cols-2'>
                <TabsTrigger value='all' className='relative'>
                  All
                  {allNotifications.length > 0 && (
                    <Badge
                      variant='secondary'
                      className='ml-1.5 size-5 rounded-full p-0 text-[10px]'
                    >
                      {allNotifications.length}
                    </Badge>
                  )}
                </TabsTrigger>
                <TabsTrigger value='unread' className='relative'>
                  Unread
                  {unreadCount > 0 && (
                    <Badge
                      variant='default'
                      className='ml-1.5 size-5 rounded-full p-0 text-[10px]'
                    >
                      {unreadCount}
                    </Badge>
                  )}
                </TabsTrigger>
              </TabsList>
            </div>

            {/* Notifications List */}
            <TabsContent value='all' className='mt-0'>
              <ScrollArea className='h-[400px]'>
                <div className='p-2'>
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
                        />
                      ))}
                    </div>
                  )}
                </div>
              </ScrollArea>
            </TabsContent>
            <TabsContent value='unread' className='mt-0'>
              <ScrollArea className='h-[400px]'>
                <div className='p-2'>
                  {unreadNotifications.length === 0 ? (
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
                      {unreadNotifications.map((notification) => (
                        <NotificationItem
                          key={notification.id}
                          notification={notification}
                        />
                      ))}
                    </div>
                  )}
                </div>
              </ScrollArea>
            </TabsContent>
          </Tabs>

          {/* Footer */}
          {allNotifications.length > 0 && (
            <>
              <Separator />
              <div className='p-3'>
                <Button
                  variant='default'
                  className='w-full'
                  onClick={() => {
                    setOpen(false)
                    window.location.href = APP_ROUTES.NOTIFICATIONS.HOME;
                  }}
                >
                  View all notifications
                </Button>
              </div>
            </>
          )}
        </div>
      </PopoverContent>
    </Popover>
  )
}

