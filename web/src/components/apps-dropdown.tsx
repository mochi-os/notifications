import { useState, useEffect } from 'react'
import { LayoutGrid } from 'lucide-react'
import axios from 'axios'
import { Button } from '@/components/ui/button'
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover'
import { ScrollArea } from '@/components/ui/scroll-area'
import { getCookie } from '@/lib/cookies'
import { useAuthStore } from '@/stores/auth-store'

interface AppIcon {
  path: string
  name: string
  file: string
}

export function AppsDropdown() {
  const [open, setOpen] = useState(false)
  const [apps, setApps] = useState<AppIcon[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open && apps.length === 0 && !error) {
      setIsLoading(true)
      setError(null)
      
      // Get auth token for the request
      const storeToken = useAuthStore.getState().token
      const cookieToken = getCookie('token')
      const token = storeToken || cookieToken
      
      // Use absolute URL to fetch icons from root
      axios
        .get<AppIcon[]>('/icons', {
          headers: token ? {
            Authorization: token.startsWith('Bearer ') ? token : `Bearer ${token}`,
          } : {},
        })
        .then((response) => {
          setApps(response.data)
        })
        .catch((err) => {
          console.error('Failed to load apps:', err)
          setError('Failed to load apps')
        })
        .finally(() => {
          setIsLoading(false)
        })
    }
  }, [open, apps.length, error])

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant='ghost'
          size='icon'
          className='relative'
          aria-label='Apps'
        >
          <LayoutGrid className='size-5' />
        </Button>
      </PopoverTrigger>
      <PopoverContent
        align='end'
        sideOffset={8}
        className='w-[340px] p-0 rounded-2xl shadow-xl border-border/50 bg-popover'
      >
        <div className='flex flex-col'>
          {/* Header */}
          <div className='flex items-center justify-between border-b px-4 py-3'>
            <h2 className='text-base font-semibold'>Apps</h2>
          </div>

          {/* Apps Grid */}
          <ScrollArea className='h-[320px]'>
            <div className='p-4'>
              {isLoading ? (
                <div className='flex items-center justify-center py-12'>
                  <div className='size-6 animate-spin rounded-full border-2 border-primary border-t-transparent' />
                </div>
              ) : error ? (
                <div className='flex flex-col items-center justify-center py-12 text-center'>
                  <LayoutGrid className='mb-4 size-12 text-muted-foreground/50' />
                  <p className='text-sm font-medium text-muted-foreground'>
                    {error}
                  </p>
                  <Button
                    variant='outline'
                    size='sm'
                    className='mt-4'
                    onClick={() => {
                      setError(null)
                      setApps([])
                    }}
                  >
                    Retry
                  </Button>
                </div>
              ) : apps.length === 0 ? (
                <div className='flex flex-col items-center justify-center py-12 text-center'>
                  <LayoutGrid className='mb-4 size-12 text-muted-foreground/50' />
                  <p className='text-sm font-medium text-muted-foreground'>
                    No apps available
                  </p>
                </div>
              ) : (
                <div className='grid grid-cols-3 gap-2'>
                  {apps.map((app) => (
                    <a
                      key={app.path}
                      href={`/${app.path}/`}
                      className='flex flex-col items-center gap-2 rounded-xl p-3 transition-colors hover:bg-accent'
                      onClick={() => setOpen(false)}
                    >
                      <div className='flex size-12 items-center justify-center rounded-xl bg-accent/50'>
                        <img
                          src={`/${app.path}/${app.file}`}
                          alt={app.name}
                          className='size-8'
                          onError={(e) => {
                            // Fallback to a generic icon if image fails to load
                            e.currentTarget.style.display = 'none'
                          }}
                        />
                      </div>
                      <span className='text-center text-xs font-medium leading-tight'>
                        {app.name}
                      </span>
                    </a>
                  ))}
                </div>
              )}
            </div>
          </ScrollArea>
        </div>
      </PopoverContent>
    </Popover>
  )
}

