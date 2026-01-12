import { useState } from 'react'
import {
  Button,
  Skeleton,
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@mochi/common'
import { MoreHorizontal, Pencil, Trash2, Bell, Loader2 } from 'lucide-react'
import { useSubscriptions, type Subscription, type SubscriptionDestination } from '@/hooks/use-subscriptions'
import { SubscriptionEditor } from './subscription-editor'

function formatAppName(app: string): string {
  if (!app) return 'Unknown'
  return app.charAt(0).toUpperCase() + app.slice(1)
}

function formatDisplayName(subscription: Subscription): string {
  return `${formatAppName(subscription.app)}: ${subscription.label}`
}

function SubscriptionItem({
  subscription,
  onEdit,
  onDelete,
  isDeleting,
}: {
  subscription: Subscription
  onEdit: () => void
  onDelete: () => void
  isDeleting: boolean
}) {
  return (
    <div className="flex items-center justify-between py-3 border-b last:border-0">
      <div className="flex items-center gap-3 flex-1 min-w-0">
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-muted shrink-0">
          <Bell className="h-4 w-4" />
        </div>
        <span className="font-medium">{formatDisplayName(subscription)}</span>
      </div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" disabled={isDeleting}>
            {isDeleting ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <MoreHorizontal className="h-4 w-4" />
            )}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={onEdit}>
            <Pencil className="mr-2 h-4 w-4" />
            Edit destinations
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={onDelete}
            className="text-destructive focus:text-destructive"
          >
            <Trash2 className="mr-2 h-4 w-4" />
            Remove
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  )
}

export function SubscriptionsManager() {
  const {
    subscriptions,
    isLoading,
    updateDestinations,
    unsubscribe,
    isUpdating,
    isDeleting,
  } = useSubscriptions()

  const [editSubscription, setEditSubscription] = useState<Subscription | null>(null)
  const [deleteSubscriptionId, setDeleteSubscriptionId] = useState<number | null>(null)

  const handleSave = async (id: number, destinations: SubscriptionDestination[]) => {
    await updateDestinations(id, destinations)
  }

  const handleDelete = async () => {
    if (deleteSubscriptionId !== null) {
      await unsubscribe(deleteSubscriptionId)
      setDeleteSubscriptionId(null)
    }
  }

  // Sort subscriptions by display name
  const sortedSubscriptions = [...subscriptions].sort((a, b) =>
    formatDisplayName(a).localeCompare(formatDisplayName(b))
  )

  return (
    <>
      {isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
        </div>
      ) : subscriptions.length === 0 ? (
        <div className="text-center py-8 text-muted-foreground">
          <p>No notifications configured. The defaults apply.</p>
        </div>
      ) : (
        <div>
          {sortedSubscriptions.map((subscription) => (
            <SubscriptionItem
              key={subscription.id}
              subscription={subscription}
              onEdit={() => setEditSubscription(subscription)}
              onDelete={() => setDeleteSubscriptionId(subscription.id)}
              isDeleting={isDeleting}
            />
          ))}
        </div>
      )}

      <SubscriptionEditor
        open={!!editSubscription}
        onOpenChange={(open) => !open && setEditSubscription(null)}
        subscription={editSubscription}
        onSave={handleSave}
        isSaving={isUpdating}
      />

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
            <AlertDialogAction onClick={handleDelete}>Remove</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
