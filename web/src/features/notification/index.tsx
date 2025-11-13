import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { Search } from '@/components/search'
import { NotificationsDropdown } from '@/components/notifications-dropdown'
import { MessagesSquare, UserPlus } from 'lucide-react'

export function Notifications() {
  return (
    <>
      <Header>
        <Search />
        <div className='ms-auto flex items-center space-x-4'>
          <NotificationsDropdown />
        </div>
      </Header>

      <Main>
        <div className='mb-6 flex items-center justify-between space-y-2'>
          <div>
            <h1 className='text-2xl font-bold tracking-tight'>Welcome to Mochi</h1>
            {/* <p className='text-muted-foreground'>
              Your home for all Mochi apps and services
            </p> */}
          </div>
        </div>

        <div className='grid gap-6 md:grid-cols-2'>
          <Card className='group hover:shadow-md transition-shadow cursor-pointer'>
            <CardHeader>
              <div className='flex items-center gap-2'>
                <MessagesSquare className='h-5 w-5 text-primary' />
                <CardTitle>Chats</CardTitle>
              </div>
              <CardDescription>
                Connect and chat with your friends
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button
                className='w-full'
                onClick={() => {
                  window.location.href = import.meta.env.VITE_APP_CHAT_URL
                }}
              >
                Open Chats
              </Button>
            </CardContent>
          </Card>

          <Card className='group hover:shadow-md transition-shadow cursor-pointer'>
            <CardHeader>
              <div className='flex items-center gap-2'>
                <UserPlus className='h-5 w-5 text-primary' />
                <CardTitle>Friends</CardTitle>
              </div>
              <CardDescription>
                Manage your friends and invitations
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button
                className='w-full'
                onClick={() => {
                  window.location.href = import.meta.env.VITE_APP_FRIENDS_URL
                }}
              >
                Open Friends
              </Button>
            </CardContent>
          </Card>
        </div>
      </Main>
    </>
  )
}


