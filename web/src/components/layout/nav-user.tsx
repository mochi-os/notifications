import { useEffect } from 'react'
import {
  ChevronsUpDown,
  LogOut,
  Settings,
  CircleUser,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { readProfileCookie } from '@/lib/profile-cookie'
import useDialogState from '@/hooks/use-dialog-state'
import { useTheme } from '@/context/theme-provider'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar'
import { SignOutDialog } from '@/components/sign-out-dialog'
import { APP_ROUTES } from '@/config/app-routes'

export function NavUser() {
  const { isMobile } = useSidebar()
  const [open, setOpen] = useDialogState()
  const { theme } = useTheme()

  // Use email from auth store (Template mirrors core auth cookie shape)
  const email = useAuthStore((state) => state.email)
  // Get name from mochi_me cookie
  const profile = readProfileCookie()
  const displayName = profile.name || 'User'
  const displayEmail = email || 'user@example.com'

  /* Update theme-color meta tag when theme is updated */
  useEffect(() => {
    const themeColor = theme === 'dark' ? '#020817' : '#fff'
    const metaThemeColor = document.querySelector("meta[name='theme-color']")
    if (metaThemeColor) metaThemeColor.setAttribute('content', themeColor)
  }, [theme])

  return (
    <>
      <SidebarMenu>
        <SidebarMenuItem>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <SidebarMenuButton
                size='lg'
                className='data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground group-data-[collapsible=icon]:!size-8 group-data-[collapsible=icon]:!p-2'
              >
                <CircleUser className='hidden size-4 group-data-[collapsible=icon]:block' />
                <div className='grid flex-1 text-start text-sm leading-tight group-data-[collapsible=icon]:hidden'>
                  <span className='truncate font-semibold'>{displayName}</span>
                  <span className='truncate text-xs'>{displayEmail}</span>
                </div>
                <ChevronsUpDown className='ms-auto size-4 group-data-[collapsible=icon]:hidden' />
              </SidebarMenuButton>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              className='w-(--radix-dropdown-menu-trigger-width) min-w-56 rounded-lg'
              side={isMobile ? 'bottom' : 'right'}
              align='end'
              sideOffset={4}
            >
              <DropdownMenuLabel className='p-0 font-normal'>
                <div className='grid px-1 py-1.5 text-start text-sm leading-tight'>
                  <span className='truncate font-semibold'>
                    {displayName}
                  </span>
                  <span className='truncate text-xs'>{displayEmail}</span>
                </div>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => {
                  setOpen(false)
                  window.location.href = APP_ROUTES.SETTINGS.HOME;
                }}
              >
                <Settings />
                Settings
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => setOpen(true)}
                variant='destructive'
                className='hover:bg-destructive/10 hover:text-destructive [&_svg]:hover:text-destructive'
              >
                <LogOut />
                Log out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </SidebarMenuItem>
      </SidebarMenu>

      <SignOutDialog open={!!open} onOpenChange={setOpen} />
    </>
  )
}
