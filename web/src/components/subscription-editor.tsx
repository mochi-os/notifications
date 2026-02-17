import { useState, useEffect, useMemo } from 'react'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Button,
  Switch,
  ListSkeleton,
  useDestinations,
  usePush,
  toast,
  push as pushLib,
  getErrorMessage,
  getAppPath,
} from '@mochi/common'
import { Bell, Loader2, Mail, Rss, Webhook, Globe, Check } from 'lucide-react'
import type { Subscription, SubscriptionDestination } from '@/hooks/use-subscriptions'

interface DestinationToggle {
  type: 'account' | 'rss'
  accountType?: string
  id: number | string
  label: string
  identifier?: string
  enabled: boolean
}

interface SubscriptionEditorProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  subscription: Subscription | null
  onSave: (id: number, destinations: SubscriptionDestination[]) => Promise<void>
  isSaving: boolean
}

function getDestinationIcon(type: string, accountType?: string) {
  if (type === 'web') {
    return <Globe className="h-4 w-4" />
  }
  if (type === 'rss') {
    return <Rss className="h-4 w-4" />
  }
  switch (accountType) {
    case 'email':
      return <Mail className="h-4 w-4" />
    case 'browser':
      return <Bell className="h-4 w-4" />
    case 'url':
      return <Webhook className="h-4 w-4" />
    default:
      return <Bell className="h-4 w-4" />
  }
}

export function SubscriptionEditor({
  open,
  onOpenChange,
  subscription,
  onSave,
  isSaving,
}: SubscriptionEditorProps) {
  const { destinations, isLoading } = useDestinations(getAppPath())
  const push = usePush()
  const [toggles, setToggles] = useState<DestinationToggle[]>([])
  const [enableWeb, setEnableWeb] = useState(true)
  const [enableBrowserPush, setEnableBrowserPush] = useState(false)
  const [isSubscribingPush, setIsSubscribingPush] = useState(false)

  // Check if browser push is already in destinations
  const hasBrowserDestination = destinations.some((d) => d.accountType === 'browser')
  // Show browser push option if supported and not already configured
  const showBrowserPushOption = push.supported && !hasBrowserDestination

  // Initialize toggles when destinations load or subscription changes
  useEffect(() => {
    if (subscription) {
      const enabledTargets = new Set(
        subscription.destinations.map((d) => `${d.type}-${d.target}`)
      )

      // Check if web is enabled in existing destinations
      setEnableWeb(enabledTargets.has('web-default'))

      setToggles(
        destinations.map((d) => ({
          type: d.type,
          accountType: d.accountType,
          id: d.id,
          label: d.label,
          identifier: d.identifier,
          enabled: enabledTargets.has(`${d.type}-${d.id}`),
        }))
      )
    }
  }, [destinations, subscription])

  // Reset toggles when dialog closes
  useEffect(() => {
    if (!open) {
      setToggles([])
      setEnableWeb(true)
      setEnableBrowserPush(false)
    }
  }, [open])

  const handleToggle = (id: number | string) => {
    setToggles((prev) =>
      prev.map((t) => (t.id === id ? { ...t, enabled: !t.enabled } : t))
    )
  }

  const handleSave = async () => {
    if (!subscription) return

    // Check if any browser destination is being enabled (new or existing)
    const hasBrowserToggleEnabled = toggles.some(
      (t) => t.enabled && t.accountType === 'browser'
    )
    const needsBrowserPermission = enableBrowserPush || hasBrowserToggleEnabled

    // If browser notifications are enabled, ensure we have permission
    if (needsBrowserPermission && pushLib.getPermission() !== 'granted') {
      setIsSubscribingPush(true)
      try {
        const permission = await pushLib.requestPermission()
        if (permission !== 'granted') {
          toast.error('Browser notification permission is required')
          setIsSubscribingPush(false)
          return
        }
      } catch (error) {
        toast.error(getErrorMessage(error, 'Failed to request notification permission'))
        setIsSubscribingPush(false)
        return
      }
    }

    // Check if existing browser account has a stale endpoint (e.g., after permission was
    // revoked and re-granted, the push subscription endpoint may have changed)
    if (hasBrowserToggleEnabled) {
      setIsSubscribingPush(true)
      try {
        const registration = await navigator.serviceWorker.ready
        const currentSubscription = await registration.pushManager.getSubscription()
        const browserToggle = toggles.find((t) => t.enabled && t.accountType === 'browser')

        if (browserToggle && currentSubscription) {
          // Check if the stored endpoint differs from the current subscription
          if (browserToggle.identifier !== currentSubscription.endpoint) {
            // Stale account detected - remove old and create new
            await push.unsubscribe()
            await push.subscribe()
            toast.success('Browser notification account has been refreshed. Please save again.')
            setIsSubscribingPush(false)
            return
          }
        } else if (browserToggle && !currentSubscription) {
          // No current subscription but browser toggle is enabled - need to resubscribe
          await push.unsubscribe() // Clean up server-side account
          await push.subscribe()
          toast.success('Browser notification account has been refreshed. Please save again.')
          setIsSubscribingPush(false)
          return
        }
      } catch (error) {
        toast.error(getErrorMessage(error, 'Failed to verify browser subscription'))
        setIsSubscribingPush(false)
        return
      }
      setIsSubscribingPush(false)
    }

    // If this is a new browser push subscription, subscribe to create the account
    let newBrowserAccountId: number | null = null
    if (enableBrowserPush && !push.subscribed) {
      setIsSubscribingPush(true)
      try {
        await push.subscribe()
        // Fetch fresh accounts list to get the new browser account ID
        const res = await fetch(`${getAppPath()}/-/accounts/list?capability=notify`, {
          credentials: 'include',
        })
        if (res.ok) {
          const data = await res.json()
          const accounts = data?.data || []
          const browserAccount = accounts.find((a: { type: string; id: number }) => a.type === 'browser')
          if (browserAccount) {
            newBrowserAccountId = browserAccount.id
          }
        }
      } catch (error) {
        toast.error(getErrorMessage(error, 'Failed to enable browser notifications'))
        setIsSubscribingPush(false)
        return
      }
      setIsSubscribingPush(false)
    }

    const enabledDestinations: SubscriptionDestination[] = []

    // Add web destination if enabled
    if (enableWeb) {
      enabledDestinations.push({ type: 'web', target: 'default' })
    }

    // Add account/rss destinations (excluding browser if we just created a new one)
    toggles
      .filter((t) => t.enabled)
      .filter((t) => !(newBrowserAccountId !== null && t.accountType === 'browser'))
      .forEach((t) => {
        enabledDestinations.push({
          type: t.type,
          target: String(t.id),
        })
      })

    // Add newly created browser account if applicable
    if (newBrowserAccountId !== null) {
      enabledDestinations.push({
        type: 'account',
        target: String(newBrowserAccountId),
      })
    }

    await onSave(subscription.id, enabledDestinations)
    onOpenChange(false)
  }

  // Build unified sorted list of all destination options
  type UnifiedItem =
    | { kind: 'web' }
    | { kind: 'browser' }
    | { kind: 'toggle'; toggle: DestinationToggle }

  const sortedItems = useMemo((): UnifiedItem[] => {
    const items: Array<{ label: string; item: UnifiedItem }> = []

    // Add Mochi web
    items.push({ label: 'Mochi web', item: { kind: 'web' } })

    // Add browser destination option with detected browser name
    if (showBrowserPushOption) {
      items.push({ label: pushLib.getBrowserName(), item: { kind: 'browser' } })
    }

    // Add all toggles (excluding browser accounts to avoid duplicates with showBrowserPushOption)
    for (const toggle of toggles) {
      // Skip browser accounts - they're handled by the showBrowserPushOption logic above
      // or shown as a regular toggle when showBrowserPushOption is false
      if (toggle.accountType === 'browser' && showBrowserPushOption) {
        continue
      }
      const displayLabel = toggle.accountType === 'email' && toggle.identifier
        ? toggle.identifier
        : toggle.label
      items.push({ label: displayLabel, item: { kind: 'toggle', toggle } })
    }

    // Sort alphabetically by label
    items.sort((a, b) => a.label.localeCompare(b.label))

    return items.map((i) => i.item)
  }, [toggles, showBrowserPushOption])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>
            {subscription?.app
              ? `${subscription.app_name || subscription.app.charAt(0).toUpperCase() + subscription.app.slice(1)}: ${subscription.label}`
              : 'Edit subscription'}
          </DialogTitle>
        </DialogHeader>

        <div className="py-4">
          {isLoading ? (
            <ListSkeleton variant="simple" height="h-12" count={2} />
          ) : (
            <div className="space-y-1">
              {sortedItems.map((item) => {
                if (item.kind === 'web') {
                  return (
                    <div key="web" className="flex items-center justify-between py-2">
                      <div className="flex items-center gap-3">
                        <Globe className="h-4 w-4 text-muted-foreground" />
                        <span className="text-sm">Mochi web</span>
                      </div>
                      <Switch
                        id="edit-toggle-web"
                        checked={enableWeb}
                        onCheckedChange={setEnableWeb}
                      />
                    </div>
                  )
                }
                if (item.kind === 'browser') {
                  return (
                    <div key="browser" className="flex items-center justify-between py-2">
                      <div className="flex items-center gap-3">
                        {getDestinationIcon('account', 'browser')}
                        <span className="text-sm">{pushLib.getBrowserName()}</span>
                      </div>
                      <Switch
                        id="edit-toggle-browser-push"
                        checked={enableBrowserPush}
                        onCheckedChange={setEnableBrowserPush}
                      />
                    </div>
                  )
                }
                const { toggle } = item
                const displayLabel = toggle.accountType === 'email' && toggle.identifier
                  ? toggle.identifier
                  : toggle.label
                return (
                  <div
                    key={`${toggle.type}-${toggle.id}`}
                    className="flex items-center justify-between py-2"
                  >
                    <div className="flex items-center gap-3">
                      <span className="text-muted-foreground">
                        {getDestinationIcon(toggle.type, toggle.accountType)}
                      </span>
                      <span className="text-sm">{displayLabel}</span>
                    </div>
                    <Switch
                      id={`edit-toggle-${toggle.type}-${toggle.id}`}
                      checked={toggle.enabled}
                      onCheckedChange={() => handleToggle(toggle.id)}
                    />
                  </div>
                )
              })}
            </div>
          )}
        </div>

        <DialogFooter className="flex-row gap-2 sm:justify-end">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={isSaving || isSubscribingPush}>
            {isSaving || isSubscribingPush ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Check className="h-4 w-4" />
            )}
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
