import { useEffect, useState } from 'react'
import {
  CircleUser,
  ChevronsUpDown,
  LogOut,
  Settings,
} from 'lucide-react'
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
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { SignOutDialog } from '@/components/sign-out-dialog'
import { APP_ROUTES } from '@/config/app-routes'

type TopBarProps = {
  children?: React.ReactNode
}

export function TopBar({ children }: TopBarProps) {
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
          'sticky top-0 z-50 h-16 w-full',
          offset > 10 ? 'shadow' : 'shadow-none'
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

          {/* Children (search, notifications, etc.) */}
          <div className="flex flex-1 items-center gap-4">
            {children}
          </div>

          {/* User Menu */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="sm" className="gap-2">
                <CircleUser className="size-5" />
                <span className="hidden sm:inline-block max-w-32 truncate">
                  {displayName}
                </span>
                <ChevronsUpDown className="size-4 hidden sm:block" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent className="w-56" align="end">
              <DropdownMenuLabel className="p-0 font-normal">
                <div className="grid px-2 py-1.5 text-start text-sm leading-tight">
                  <span className="truncate font-semibold">{displayName}</span>
                  <span className="truncate text-xs text-muted-foreground">
                    {displayEmail}
                  </span>
                </div>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => {
                  window.location.href = APP_ROUTES.SETTINGS.HOME
                }}
              >
                <Settings className="size-4" />
                Settings
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => setOpen(true)}
                variant="destructive"
                className="hover:bg-destructive/10 hover:text-destructive [&_svg]:hover:text-destructive"
              >
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
