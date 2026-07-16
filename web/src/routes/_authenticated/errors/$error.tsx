// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { createFileRoute } from '@tanstack/react-router'
import { ConfigDrawer } from '@mochi/web/components/config-drawer'
import { Header } from '@mochi/web/components/layout/header'
import { ProfileDropdown } from '@mochi/web/components/profile-dropdown'
import { Search } from '@mochi/web/components/search'
import { ThemeSwitch } from '@mochi/web/components/theme-switch'
import { ForbiddenError } from '@mochi/web/features/errors/forbidden'
import { GeneralError } from '@mochi/web/features/errors/general-error'
import { MaintenanceError } from '@mochi/web/features/errors/maintenance-error'
import { NotFoundError } from '@mochi/web/features/errors/not-found-error'
import { UnauthorisedError } from '@mochi/web/features/errors/unauthorized-error'

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
