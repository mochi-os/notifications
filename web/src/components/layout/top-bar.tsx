import { useEffect, useState } from 'react'
import { CircleUser, LogOut, Settings } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAuthStore } from '@/stores/auth-store'
import { readProfileCookie } from '@/lib/profile-cookie'
import { useTheme } from '@/context/theme-provider'
import useDialogState from '@/hooks/use-dialog-state'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { SignOutDialog } from '@/components/sign-out-dialog'
import { APP_ROUTES } from '@/config/app-routes'

export function TopBar() {
  const [offset, setOffset] = useState(0)
  const [open, setOpen] = useDialogState()
  const { theme } = useTheme()

  const email = useAuthStore((state) => state.email)
  const profile = readProfileCookie()
  const displayName = profile.name || 'User'
  const displayEmail = email || 'user@example.com'

  useEffect(() => {
    const onScroll = () => {
      setOffset(document.body.scrollTop || document.documentElement.scrollTop)
    }
    document.addEventListener('scroll', onScroll, { passive: true })
    return () => document.removeEventListener('scroll', onScroll)
  }, [])

  useEffect(() => {
    const themeColor = theme === 'dark' ? '#020817' : '#fff'
    const metaThemeColor = document.querySelector("meta[name='theme-color']")
    if (metaThemeColor) metaThemeColor.setAttribute('content', themeColor)
  }, [theme])

  return (
    <>
      <header
        className={cn(
          'sticky top-0 z-50 h-16 w-full shadow-sm',
          offset > 10 && 'shadow'
        )}
      >
        <div
          className={cn(
            'relative flex h-full items-center gap-4 px-4 sm:px-6',
            offset > 10 &&
              'after:bg-background/80 after:absolute after:inset-0 after:-z-10 after:backdrop-blur-lg'
          )}
        >
          {/* Logo */}
          <a href="/" className="flex items-center">
            <img
              src="/images/logo-header.svg"
              alt="Mochi"
              className="h-8 w-8"
            />
          </a>

          <div className="flex-1" />

          {/* User Menu */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon">
                <CircleUser className="size-5" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent className="min-w-56" align="end">
              <DropdownMenuLabel className="p-0 font-normal">
                <div className="grid px-2 py-1.5 text-start text-sm leading-tight">
                  <span className="font-semibold">{displayName}</span>
                  <span className="text-xs text-muted-foreground">
                    {displayEmail}
                  </span>
                </div>
              </DropdownMenuLabel>
              <DropdownMenuItem
                onClick={() => {
                  window.location.href = APP_ROUTES.SETTINGS.HOME
                }}
              >
                <Settings className="size-4" />
                Settings
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setOpen(true)}>
                <LogOut className="size-4" />
                Log out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </header>

      <SignOutDialog open={!!open} onOpenChange={setOpen} />
    </>
  )
}
