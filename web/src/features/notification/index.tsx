import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { Search } from '@/components/search'
import { NotificationsDropdown } from '@/components/notifications-dropdown'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ScrollArea } from '@/components/ui/scroll-area'
import {
  Card,
  CardContent,
} from '@/components/ui/card'
import { NotificationsEmptyState } from '@/components/notifications-empty-state'

export function Notifications() {
  const [activeTab, setActiveTab] = useState('all')
  const totalNotifications = 0
  const unreadCount = 0
  const hasNotifications = totalNotifications > 0

  const handleMarkAllAsRead = () => {
    // In a real app, this would update the notifications state
    console.log('Mark all as read')
  }

  const renderEmptyState = () => (
    <ScrollArea className='h-[calc(100vh-310px)]'>
      <div className='p-4'>
        <NotificationsEmptyState />
      </div>
    </ScrollArea>
  )

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
              Mark all as read
            </Button>
          )}
        </div>

        {/* Tabs */}
        <Tabs value={activeTab} onValueChange={setActiveTab} className=''>
          <TabsList className='grid w-full max-w-md grid-cols-2'>
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

          {/* Notifications List */}
          <TabsContent value='all' className='mt-6'>
            <Card>
              <CardContent className='p-0'>
                {renderEmptyState()}
              </CardContent>
            </Card>
          </TabsContent>
          <TabsContent value='unread' className='mt-6'>
            <Card>
              <CardContent className='p-0'>
                {renderEmptyState()}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </Main>
    </>
  )
}


