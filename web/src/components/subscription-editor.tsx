import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Button,
  Switch,
  Skeleton,
  useDestinations,
} from '@mochi/common'
import { Loader2, Bell, Mail, Rss, Webhook } from 'lucide-react'
import type { Subscription, SubscriptionDestination } from '@/hooks/use-subscriptions'

interface DestinationToggle {
  type: 'account' | 'rss'
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
  const { destinations, isLoading } = useDestinations('/notifications')
  const [toggles, setToggles] = useState<DestinationToggle[]>([])

  // Initialize toggles when destinations load or subscription changes
  useEffect(() => {
    if (destinations.length > 0 && subscription) {
      const enabledTargets = new Set(
        subscription.destinations.map((d) => `${d.type}-${d.target}`)
      )

      setToggles(
        destinations.map((d) => ({
          type: d.type,
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
    }
  }, [open])

  const handleToggle = (id: number | string) => {
    setToggles((prev) =>
      prev.map((t) => (t.id === id ? { ...t, enabled: !t.enabled } : t))
    )
  }

  const handleSave = async () => {
    if (!subscription) return

    const enabledDestinations: SubscriptionDestination[] = toggles
      .filter((t) => t.enabled)
      .map((t) => ({
        type: t.type,
        target: String(t.id),
      }))

    await onSave(subscription.id, enabledDestinations)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Edit subscription</DialogTitle>
          {subscription && (
            <DialogDescription>
              {subscription.label}
              <span className="block text-xs mt-1">From: {subscription.app}</span>
            </DialogDescription>
          )}
        </DialogHeader>

        <div className="py-4">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
            </div>
          ) : toggles.length === 0 ? (
            <div className="text-center py-4 text-muted-foreground">
              <p>No notification destinations available.</p>
            </div>
          ) : (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground mb-3">
                Choose where to receive these notifications:
              </p>
              {toggles.map((toggle) => (
                <div
                  key={`${toggle.type}-${toggle.id}`}
                  className="flex items-center justify-between rounded-lg border p-3"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
                      {getDestinationIcon(toggle.type, toggle.label)}
                    </div>
                    <div>
                      <div className="font-medium text-sm">{toggle.label}</div>
                      {toggle.identifier && (
                        <div className="text-xs text-muted-foreground">
                          {toggle.identifier}
                        </div>
                      )}
                    </div>
                  </div>
                  <Switch
                    id={`edit-toggle-${toggle.type}-${toggle.id}`}
                    checked={toggle.enabled}
                    onCheckedChange={() => handleToggle(toggle.id)}
                  />
                </div>
              ))}
            </div>
          )}
        </div>

        <DialogFooter className="flex-row gap-2 sm:justify-end">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={isSaving}>
            {isSaving && <Loader2 className="h-4 w-4 animate-spin" />}
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
