import { Bell } from 'lucide-react'

export function NotificationsEmptyState() {
  return (
    <div className='flex flex-col items-center justify-center py-12 text-center'>
      <Bell className='mb-4 size-12 text-muted-foreground/50' />
      <p className='text-sm font-medium text-muted-foreground'>You're all caught up!</p>
      <p className='mt-1 text-xs text-muted-foreground/80'>
        We'll let you know when there's something new.
      </p>
    </div>
  )
}

