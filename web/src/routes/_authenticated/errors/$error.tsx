import { createFileRoute } from '@tanstack/react-router'
import { ConfigDrawer } from '@mochi/common/components/config-drawer'
import { Header } from '@mochi/common/components/layout/header'
import { ProfileDropdown } from '@mochi/common/components/profile-dropdown'
import { Search } from '@mochi/common/components/search'
import { ThemeSwitch } from '@mochi/common/components/theme-switch'
import { ForbiddenError } from '@mochi/common/features/errors/forbidden'
import { GeneralError } from '@mochi/common/features/errors/general-error'
import { MaintenanceError } from '@mochi/common/features/errors/maintenance-error'
import { NotFoundError } from '@mochi/common/features/errors/not-found-error'
import { UnauthorisedError } from '@mochi/common/features/errors/unauthorized-error'

export const Route = createFileRoute('/_authenticated/errors/$error')({
  component: RouteComponent,
})

function RouteComponent() {
  const { error } = Route.useParams()

  const errorMap: Record<string, React.ComponentType> = {
    unauthorized: UnauthorisedError,
    forbidden: ForbiddenError,
    'not-found': NotFoundError,
    'internal-server-error': GeneralError,
    'maintenance-error': MaintenanceError,
  }
  const ErrorComponent = errorMap[error] || NotFoundError

  return (
    <>
      <Header fixed className='border-b'>
        <Search />
        <div className='ms-auto flex items-center space-x-4'>
          <ThemeSwitch />
          <ConfigDrawer />
          <ProfileDropdown />
        </div>
      </Header>
      <div className='flex-1 [&>div]:h-full'>
        <ErrorComponent />
      </div>
    </>
  )
}
