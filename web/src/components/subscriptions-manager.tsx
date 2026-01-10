import { useState } from 'react'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Button,
  Badge,
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

function formatDate(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleDateString()
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
  const destinationCount = subscription.destinations.length

  return (
    <div className="flex items-center justify-between py-3 border-b last:border-0">
      <div className="flex items-center gap-3 flex-1 min-w-0">
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-muted shrink-0">
          <Bell className="h-4 w-4" />
        </div>
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium truncate">{subscription.label}</span>
            <Badge variant="secondary" className="text-xs shrink-0">
              {subscription.app}
            </Badge>
          </div>
          <div className="text-sm text-muted-foreground">
            {destinationCount === 0 ? (
              <span className="text-amber-600 dark:text-amber-400">No destinations</span>
            ) : (
              <span>
                {destinationCount} destination{destinationCount !== 1 ? 's' : ''}
              </span>
            )}{' '}
            &middot; Created {formatDate(subscription.created)}
          </div>
        </div>
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
            Unsubscribe
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

  // Group subscriptions by app
  const groupedSubscriptions = subscriptions.reduce(
    (acc, sub) => {
      if (!acc[sub.app]) {
        acc[sub.app] = []
      }
      acc[sub.app].push(sub)
      return acc
    },
    {} as Record<string, Subscription[]>
  )

  const appNames = Object.keys(groupedSubscriptions).sort()

  return (
    <>
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Subscriptions</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-2">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : subscriptions.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              <p>No subscriptions</p>
              <p className="text-sm mt-1">
                Apps will ask for permission before sending you notifications.
              </p>
            </div>
          ) : (
            <div>
              {appNames.map((appName) => (
                <div key={appName}>
                  {groupedSubscriptions[appName].map((subscription) => (
                    <SubscriptionItem
                      key={subscription.id}
                      subscription={subscription}
                      onEdit={() => setEditSubscription(subscription)}
                      onDelete={() => setDeleteSubscriptionId(subscription.id)}
                      isDeleting={isDeleting}
                    />
                  ))}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

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
            <AlertDialogTitle>Unsubscribe?</AlertDialogTitle>
            <AlertDialogDescription>
              You will no longer receive notifications for this subscription. The app may
              ask for permission again if you interact with it.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete}>Unsubscribe</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
