// Copyright © 2026 Mochi OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { useMemo } from 'react'
import { Trans, useLingui } from '@lingui/react/macro'
import {
  PageHeader,
  Main,
  EmptyState,
  ListSkeleton,
  GeneralError,
  NotificationCategoryButton,
  NotificationSourceIcon,
  useFormat,
  getSafeNavigationTarget,
  shellNavigateExternal,
  toast,
  useShellStorage,
  usePageTitle,
} from '@mochi/web'
import { Button } from '@mochi/web/components/ui/button'
import { Label } from '@mochi/web/components/ui/label'
import { Switch } from '@mochi/web/components/ui/switch'
import { cn } from '@mochi/web/lib/utils'
import {
  Bell,
  Check,
  Loader2,
  Trash2,
} from 'lucide-react'
import type { Notification as ApiNotification } from '@/api/notifications'
import { useNotificationWebSocket } from '@/hooks/useNotificationWebSocket'
import {
  useNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useClearAllMutation,
} from '@/hooks/useNotifications'

const STORAGE_KEY = 'notifications-show-all'
const TRUSTED_EXTERNAL_REDIRECT_HOSTS = (
  import.meta.env.VITE_TRUSTED_REDIRECT_HOSTS ?? ''
)
  .split(',')
  .map((host: string) => host.trim().toLowerCase())
  .filter(Boolean)

function NotificationItem({
  notification,
  onMarkAsRead,
}: {
  notification: ApiNotification
  onMarkAsRead: (id: string) => void
}) {
  const { t } = useLingui()
  const { formatTimestamp } = useFormat()
  const isUnread = notification.read === 0

  const handleClick = () => {
    if (isUnread) {
      onMarkAsRead(notification.id)
    }

    if (notification.link) {
      const safeTarget = getSafeNavigationTarget(
        notification.link,
        window.location.origin,
        {
          trustedExternalHosts: TRUSTED_EXTERNAL_REDIRECT_HOSTS,
        }
      )
      if (safeTarget) {
        shellNavigateExternal(safeTarget)
      } else {
        toast.error(t`Blocked navigation to untrusted link`)
      }
    }
  }

  return (
    <div
      className={cn(
        'hover:bg-hover flex w-full items-start gap-3 px-4 py-3 transition-colors first:rounded-t-[10px] last:rounded-b-[10px]',
        isUnread && 'bg-selected/50'
      )}
    >
      <button
        type='button'
        onClick={handleClick}
        className='flex flex-1 items-start gap-3 text-start'
      >
        <NotificationSourceIcon
          app={notification.app}
          sender={notification.sender}
          isUnread={isUnread}
        />
        <div className='min-w-0 flex-1'>
          <p className='text-sm leading-snug'>
            {notification.content}
            {notification.count > 1 && (
              <span className='text-muted-foreground'>
                {' '}
                ({notification.count})
              </span>
            )}
          </p>
          <p className='text-muted-foreground mt-0.5 text-xs'>
            {formatTimestamp(notification.created)}
          </p>
        </div>
      </button>
      <NotificationCategoryButton
        app={notification.app}
        topic={notification.topic}
        object={notification.object}
        className='mt-0.5 shrink-0'
      />
    </div>
  )
}

export function Notifications() {
  const { t } = useLingui()
  usePageTitle(t`Notifications`)
  const [showAll, setShowAll] = useShellStorage(STORAGE_KEY, false)

  const { data, isLoading, error, refetch } = useNotificationsQuery()

  useNotificationWebSocket()
  const markAsReadMutation = useMarkAsReadMutation()
  const markAllAsReadMutation = useMarkAllAsReadMutation()
  const clearAllMutation = useClearAllMutation()

  const allNotifications = useMemo(() => data?.data ?? [], [data])
  const unreadCount = useMemo(
    () => allNotifications.filter((n) => n.read === 0).length,
    [allNotifications]
  )

  const displayedNotifications = showAll
    ? allNotifications
    : allNotifications.filter((n) => n.read === 0)

  const handleMarkAsRead = (id: string) => {
    markAsReadMutation.mutate(id)
  }

  const handleMarkAllAsRead = () => {
    markAllAsReadMutation.mutate()
  }

  const handleClearAll = () => {
    clearAllMutation.mutate()
  }

  return (
    <>
      <PageHeader
        title={t`Notifications`}
        icon={<Bell className='size-4 md:size-5' />}
        actions={
          <>
            <div className='me-2 flex items-center gap-2'>
              <Label
                htmlFor='show-all'
                className='text-muted-foreground hidden text-sm md:block'
              >
                <Trans>Show all</Trans>
              </Label>
              <Switch
                id='show-all'
                checked={showAll}
                onCheckedChange={setShowAll}
              />
            </div>
            {unreadCount > 0 && (
              <Button
                variant='ghost'
                size='sm'
                onClick={handleMarkAllAsRead}
                disabled={markAllAsReadMutation.isPending}
              >
                {markAllAsReadMutation.isPending ? (
                  <Loader2 className='me-1.5 size-4 animate-spin' />
                ) : (
                  <Check className='me-1.5 size-4' />
                )}
                <span className='hidden md:inline'><Trans>Mark all read</Trans></span>
              </Button>
            )}
            {allNotifications.length > 0 && (
              <Button
                variant='ghost'
                size='sm'
                onClick={handleClearAll}
                disabled={clearAllMutation.isPending}
              >
                {clearAllMutation.isPending ? (
                  <Loader2 className='me-1.5 size-4 animate-spin' />
                ) : (
                  <Trash2 className='me-1.5 size-4' />
                )}
                <span className='hidden md:inline'><Trans>Clear all</Trans></span>
              </Button>
            )}
          </>
        }
      />
      <Main>
        <div>
          {/* Loading */}
          {isLoading && (
            <ListSkeleton
              count={5}
              variant='simple'
              avatar
              className='divide-y px-2'
            />
          )}

          {/* Error */}
          {error && (
            <div className='py-12'>
              <GeneralError
                error={error}
                minimal
                mode='inline'
                reset={() => void refetch()}
              />
            </div>
          )}

          {/* List */}
          {!isLoading && !error && (
            <>
              {displayedNotifications.length === 0 ? (
                <div className='py-12'>
                  <EmptyState
                    icon={Bell}
                    title={
                      showAll ? t`No notifications` : t`No unread notifications`
                    }
                  />
                </div>
              ) : (
                <div className='divide-y'>
                  {displayedNotifications.map((notification) => (
                    <NotificationItem
                      key={notification.id}
                      notification={notification}
                      onMarkAsRead={handleMarkAsRead}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </Main>
    </>
  )
}
