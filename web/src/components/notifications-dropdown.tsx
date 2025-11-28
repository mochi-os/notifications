import { useState } from 'react'
import { Bell } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Separator } from '@/components/ui/separator'
import { getPath } from '@mochi/config/routes'
import { NotificationsEmptyState } from '@/components/notifications-empty-state'

export function NotificationsDropdown() {
  const [open, setOpen] = useState(false)
  const [activeTab, setActiveTab] = useState('all')
  const totalNotifications = 0
  const unreadCount = 0
  const hasNotifications = totalNotifications > 0

  const handleMarkAllAsRead = () => {
    // In a real app, this would update the notifications state
    console.log('Mark all as read')
  }

  const renderEmptyState = () => (
    <ScrollArea className='h-[400px]'>
      <div className='p-4'>
        <NotificationsEmptyState />
      </div>
    </ScrollArea>
  )

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
                  {hasNotifications && (
                    <Badge
                      variant='secondary'
                      className='ml-1.5 size-5 rounded-full p-0 text-[10px]'
                    >
                      {totalNotifications}
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
              {renderEmptyState()}
            </TabsContent>
            <TabsContent value='unread' className='mt-0'>
              {renderEmptyState()}
            </TabsContent>
          </Tabs>

          {/* Footer */}
          {hasNotifications && (
            <>
              <Separator />
              <div className='p-3'>
                <Button
                  variant='default'
                  className='w-full'
                  onClick={() => {
                    setOpen(false)
                    window.location.href = getPath('notifications');
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

