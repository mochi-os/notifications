import { useEffect, useState } from 'react'
import { CircleUser, LogOut } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAuthStore } from '@/stores/auth-store'
import { readProfileCookie } from '@/lib/profile-cookie'
import { useTheme } from '@/context/theme-provider'
import useDialogState from '@/hooks/use-dialog-state'
import { Button } from '@/components/ui/button'
import { NotificationsDropdown } from '@/components/notifications-dropdown'
import { AppsDropdown } from '@/components/apps-dropdown'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { SignOutDialog } from '@/components/sign-out-dialog'
import { DropdownMenuSeparator } from '@radix-ui/react-dropdown-menu'

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
          <a href="/" className="flex shrink-0 items-center">
            <img
              src="./images/logo-header.svg"
              alt="Mochi"
              className="h-8 w-8"
            />
          </a>

          {/* Page Title */}
          <h1 className="absolute left-1/2 -translate-x-1/2 text-xl font-light tracking-tight"  >Notifications</h1>

          <div className="flex-1" />

          {/* Right Side Icons */}
          <div className="flex shrink-0 items-center gap-1">

            {/* Notifications */}
            <NotificationsDropdown />

            {/* Apps Dropdown */}
            <AppsDropdown />
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
                <DropdownMenuSeparator className="my-1 h-px bg-muted" />
                <DropdownMenuItem
                  onClick={() => setOpen(true)}
                  className="bg-red-50 text-red-600 focus:bg-red-100 focus:text-red-600"
                >
                  <LogOut className="mr-2 size-4 text-red-600" />
                  Log out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </header>

      <SignOutDialog open={!!open} onOpenChange={setOpen} />
    </>
  )
}
