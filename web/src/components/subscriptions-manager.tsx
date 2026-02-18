import { useState, useMemo, useCallback } from 'react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  Checkbox,
  EmptyState,
  Skeleton,
  useDestinations,
  usePush,
  push as pushLib,
  toast,
  getErrorMessage,
  getAppPath,
} from '@mochi/common'
import type { Destination } from '@mochi/common'
import { Bell, Globe, Mail, Rss, Trash2, Webhook } from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { useSubscriptions, type Subscription, type SubscriptionDestination } from '@/hooks/use-subscriptions'

function formatDisplayName(sub: Subscription): string {
  const appName = sub.app_name || sub.app.charAt(0).toUpperCase() + sub.app.slice(1)
  return `${appName}: ${sub.label}`
}

function destinationIcon(type: string, accountType?: string) {
  if (type === 'rss') return <Rss className='size-3.5' />
  switch (accountType) {
    case 'email': return <Mail className='size-3.5' />
    case 'browser': return <Bell className='size-3.5' />
    case 'url': return <Webhook className='size-3.5' />
    default: return <Bell className='size-3.5' />
  }
}

function destinationLabel(d: Destination): string {
  if (d.accountType === 'email' && d.identifier) return d.identifier
  return d.label
}

type Column =
  | { kind: 'web' }
  | { kind: 'destination'; destination: Destination }
  | { kind: 'browser-push' }

export function SubscriptionsManager() {
  const queryClient = useQueryClient()
  const { subscriptions, isLoading, updateDestinations, unsubscribe, isDeleting } = useSubscriptions()
  const appBase = getAppPath()
  const { destinations, isLoading: destinationsLoading } = useDestinations(appBase)
  const push = usePush()

  const [deleteSubscriptionId, setDeleteSubscriptionId] = useState<number | null>(null)
  // Optimistic destinations keyed by subscription ID
  const [optimistic, setOptimistic] = useState<Record<number, SubscriptionDestination[]>>({})
  // Subscription IDs currently saving (prevent concurrent saves per row)
  const [savingRows, setSavingRows] = useState<Set<number>>(new Set())

  const hasBrowserDestination = destinations.some((d) => d.accountType === 'browser')
  const showBrowserPushOption = push.supported && !hasBrowserDestination

  const columns = useMemo((): Column[] => {
    const cols: Column[] = [{ kind: 'web' }]
    const sorted = [...destinations].sort((a, b) =>
      destinationLabel(a).localeCompare(destinationLabel(b))
    )
    for (const d of sorted) {
      cols.push({ kind: 'destination', destination: d })
    }
    if (showBrowserPushOption) {
      cols.push({ kind: 'browser-push' })
    }
    return cols
  }, [destinations, showBrowserPushOption])

  const sortedSubscriptions = useMemo(
    () => [...subscriptions].sort((a, b) => formatDisplayName(a).localeCompare(formatDisplayName(b))),
    [subscriptions]
  )

  function getEffectiveDestinations(sub: Subscription): SubscriptionDestination[] {
    return optimistic[sub.id] ?? sub.destinations
  }

  function isChecked(sub: Subscription, type: string, target: string): boolean {
    return getEffectiveDestinations(sub).some((d) => d.type === type && d.target === target)
  }

  // Verify a browser push endpoint isn't stale. Returns the new account ID
  // target if refreshed, or the original target if the endpoint is fresh.
  async function refreshBrowserIfStale(dest: Destination): Promise<string> {
    const target = String(dest.id)
    try {
      const registration = await navigator.serviceWorker.ready
      const currentSub = await registration.pushManager.getSubscription()

      if (currentSub && dest.identifier === currentSub.endpoint) {
        return target // endpoint is fresh
      }

      // Stale or missing push subscription — refresh
      await push.unsubscribe()
      await push.subscribe()

      // Fetch accounts to get the (possibly new) browser account ID
      const res = await fetch(`${appBase}/-/accounts/list?capability=notify`, {
        credentials: 'include',
      })
      if (res.ok) {
        const data = await res.json()
        const accounts = data?.data || []
        const browserAccount = accounts.find((a: { type: string; id: number }) => a.type === 'browser')
        if (browserAccount) {
          queryClient.invalidateQueries({ queryKey: ['destinations'] })
          return String(browserAccount.id)
        }
      }
    } catch (error) {
      toast.error(getErrorMessage(error, 'Failed to verify browser subscription'))
    }
    return target
  }

  const handleToggle = useCallback(
    async (sub: Subscription, type: SubscriptionDestination['type'], target: string) => {
      if (savingRows.has(sub.id)) return

      const current = getEffectiveDestinations(sub)
      const exists = current.some((d) => d.type === type && d.target === target)

      let effectiveTarget = target

      // When toggling ON a browser destination, verify the endpoint isn't stale
      if (!exists && type === 'account') {
        const dest = destinations.find((d) => d.type === type && String(d.id) === target)
        if (dest?.accountType === 'browser') {
          setSavingRows((prev) => new Set(prev).add(sub.id))
          effectiveTarget = await refreshBrowserIfStale(dest)
        }
      }

      const next = exists
        ? current.filter((d) => !(d.type === type && d.target === target))
        : [...current, { type, target: effectiveTarget }]

      setOptimistic((prev) => ({ ...prev, [sub.id]: next }))
      setSavingRows((prev) => new Set(prev).add(sub.id))

      try {
        await updateDestinations(sub.id, next)
      } finally {
        setOptimistic((prev) => {
          const { [sub.id]: _, ...rest } = prev
          return rest
        })
        setSavingRows((prev) => {
          const s = new Set(prev)
          s.delete(sub.id)
          return s
        })
      }
    },
    [savingRows, optimistic, subscriptions, updateDestinations, destinations, push, appBase, queryClient]
  )

  const handleBrowserToggle = useCallback(
    async (sub: Subscription) => {
      if (savingRows.has(sub.id)) return

      setSavingRows((prev) => new Set(prev).add(sub.id))

      try {
        // Request notification permission
        if (pushLib.getPermission() !== 'granted') {
          const permission = await pushLib.requestPermission()
          if (permission !== 'granted') {
            toast.error('Browser notification permission is required')
            return
          }
        }

        // Subscribe to push (creates browser account on server)
        await push.subscribe()

        // Fetch accounts to get the new browser account ID
        const res = await fetch(`${appBase}/-/accounts/list?capability=notify`, {
          credentials: 'include',
        })
        if (!res.ok) {
          toast.error('Failed to get browser account')
          return
        }
        const data = await res.json()
        const accounts = data?.data || []
        const browserAccount = accounts.find((a: { type: string; id: number }) => a.type === 'browser')
        if (!browserAccount) {
          toast.error('Browser account not found')
          return
        }

        // Save with new browser destination added
        const current = getEffectiveDestinations(sub)
        const next = [...current, { type: 'account' as const, target: String(browserAccount.id) }]

        setOptimistic((prev) => ({ ...prev, [sub.id]: next }))
        await updateDestinations(sub.id, next)

        // Refetch destinations so the browser column appears as a regular destination
        queryClient.invalidateQueries({ queryKey: ['destinations'] })
      } catch (error) {
        toast.error(getErrorMessage(error, 'Failed to enable browser notifications'))
      } finally {
        setOptimistic((prev) => {
          const { [sub.id]: _, ...rest } = prev
          return rest
        })
        setSavingRows((prev) => {
          const s = new Set(prev)
          s.delete(sub.id)
          return s
        })
      }
    },
    [savingRows, optimistic, subscriptions, updateDestinations, push, appBase, queryClient]
  )

  const handleDelete = async () => {
    if (deleteSubscriptionId !== null) {
      await unsubscribe(deleteSubscriptionId)
      setDeleteSubscriptionId(null)
    }
  }

  if (isLoading || destinationsLoading) {
    return (
      <div className='space-y-2 p-4'>
        <Skeleton className='h-8 w-full' />
        <Skeleton className='h-8 w-full' />
        <Skeleton className='h-8 w-full' />
      </div>
    )
  }

  if (subscriptions.length === 0) {
    return (
      <EmptyState
        icon={Bell}
        title='No notifications configured'
        description='The defaults apply.'
        className='py-8'
      />
    )
  }

  return (
    <>
      <div>
        <table className='w-full text-sm'>
          <thead>
            <tr className='border-b text-muted-foreground'>
              <th className='py-2 px-4' />
              {columns.map((col, i) => {
                let icon: React.ReactNode
                let label: string
                if (col.kind === 'web') {
                  icon = <Globe className='size-3.5' />
                  label = 'Web'
                } else if (col.kind === 'destination') {
                  icon = destinationIcon(col.destination.type, col.destination.accountType)
                  label = destinationLabel(col.destination)
                } else {
                  icon = <Bell className='size-3.5' />
                  label = pushLib.getBrowserName()
                }
                return (
                  <th key={i} className='font-medium p-0 align-bottom'>
                    <div className='flex flex-col items-center pb-2 gap-3'>
                      <span
                        className='[writing-mode:vertical-rl] -rotate-45 origin-bottom whitespace-nowrap text-xs'
                        title={label}
                      >
                        {label}
                      </span>
                      <span className='text-muted-foreground shrink-0'>{icon}</span>
                    </div>
                  </th>
                )
              })}
              <th className='w-10' />
            </tr>
          </thead>
          <tbody>
            {sortedSubscriptions.map((sub) => (
              <tr key={sub.id} className='border-b last:border-b-0'>
                <td className='py-2.5 px-4 font-medium'>{formatDisplayName(sub)}</td>
                {columns.map((col, i) => {
                  if (col.kind === 'web') {
                    return (
                      <td key={i} className='py-2.5 px-2 text-center'>
                        <Checkbox
                          checked={isChecked(sub, 'web', 'default')}
                          disabled={savingRows.has(sub.id)}
                          onCheckedChange={() => handleToggle(sub, 'web', 'default')}
                        />
                      </td>
                    )
                  }
                  if (col.kind === 'destination') {
                    const d = col.destination
                    return (
                      <td key={i} className='py-2.5 px-2 text-center'>
                        <Checkbox
                          checked={isChecked(sub, d.type, String(d.id))}
                          disabled={savingRows.has(sub.id)}
                          onCheckedChange={() => handleToggle(sub, d.type, String(d.id))}
                        />
                      </td>
                    )
                  }
                  if (col.kind === 'browser-push') {
                    return (
                      <td key={i} className='py-2.5 px-2 text-center'>
                        <Checkbox
                          checked={false}
                          disabled={savingRows.has(sub.id)}
                          onCheckedChange={() => handleBrowserToggle(sub)}
                        />
                      </td>
                    )
                  }
                  return null
                })}
                <td className='py-2.5 px-2 text-center'>
                  <button
                    className='text-muted-foreground hover:text-destructive transition-colors p-1'
                    onClick={() => setDeleteSubscriptionId(sub.id)}
                    disabled={isDeleting}
                  >
                    <Trash2 className='size-4' />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <AlertDialog
        open={deleteSubscriptionId !== null}
        onOpenChange={() => setDeleteSubscriptionId(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove?</AlertDialogTitle>
            <AlertDialogDescription>
              You will no longer receive notifications for this subscription. The app may
              ask for permission again if you interact with it.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction variant='destructive' onClick={handleDelete}>Remove</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
