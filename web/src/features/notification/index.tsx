import { useState } from 'react'
import {
  Bell,
  BellRing,
  Check,
  Heart,
  MessageSquare,
  UserPlus,
  X,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { Search } from '@/components/search'
import { NotificationsDropdown } from '@/components/notifications-dropdown'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import {
  Card,
  CardContent,
} from '@/components/ui/card'

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
        'group relative flex gap-3 rounded-lg p-4 transition-colors hover:bg-accent',
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
            <p className='text-sm font-medium leading-tight'>
              <span className='font-semibold'>{notification.name}</span>{' '}
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
                <X className='mr-1.5 h-3.5 w-3.5' />
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
              <Check className='mr-1.5 h-3.5 w-3.5' />
              {notification.actionButtons.primary}
            </Button>
          </div>
        )}

        <p className='text-xs text-muted-foreground'>{notification.timestamp}</p>
      </div>
    </div>
  )
}

export function Notifications() {
  const [activeTab, setActiveTab] = useState('all')

  const allNotifications: Notification[] = []
  const unreadNotifications: Notification[] = []
  const unreadCount = unreadNotifications.length

  const handleMarkAllAsRead = () => {
    // In a real app, this would update the notifications state
    console.log('Mark all as read')
  }

  return (
    <>
      <Header>
        <Search />
        <div className='ms-auto flex items-center space-x-4'>
          <NotificationsDropdown />
        </div>
      </Header>

      <Main>
        {/* Page Header */}
        <div className='mb-6 flex items-center justify-between space-y-2'>
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
              className='text-sm'
            >
              <Check className='mr-2 h-4 w-4' />
              Mark all as read
            </Button>
          )}
        </div>

        {/* Tabs */}
        <Tabs value={activeTab} onValueChange={setActiveTab} className=''>
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
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </Main>
    </>
  )
}

