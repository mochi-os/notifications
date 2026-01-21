import { useState } from 'react'
import {
  Button,
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
  EmptyState,
} from '@mochi/common'
import { CardContent } from '@mochi/common/components/ui/card'
import { MoreHorizontal, Pencil, Trash2, Bell, Loader2 } from 'lucide-react'
import { useSubscriptions, type Subscription, type SubscriptionDestination } from '@/hooks/use-subscriptions'
import { SubscriptionEditor } from './subscription-editor'

function formatDisplayName(subscription: Subscription): string {
  const appName = subscription.app_name || subscription.app.charAt(0).toUpperCase() + subscription.app.slice(1)
  return `${appName}: ${subscription.label}`
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
    <div className='flex items-center justify-between px-4 py-3'>
      <div className='flex items-center gap-3 flex-1 min-w-0'>
        <div className='flex h-9 w-9 items-center justify-center rounded-full bg-muted shrink-0'>
          <Bell className='size-4' />
        </div>
        <span className='font-medium'>{formatDisplayName(subscription)}</span>
      </div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant='ghost' size='icon' disabled={isDeleting}>
            {isDeleting ? (
              <Loader2 className='size-4 animate-spin' />
            ) : (
              <MoreHorizontal className='size-4' />
            )}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align='end'>
          <DropdownMenuItem onClick={onEdit}>
            <Pencil className='mr-2 size-4' />
            Edit destinations
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={onDelete}
            className='text-destructive focus:text-destructive'
          >
            <Trash2 className='mr-2 size-4' />
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
        <CardContent>
          <EmptyState
            icon={Loader2}
            title='Loading subscriptions...'
            className='animate-pulse opacity-70 py-8'
          />
        </CardContent>
      ) : subscriptions.length === 0 ? (
        <CardContent>
          <EmptyState
            icon={Bell}
            title='No notifications configured'
            description='The defaults apply.'
            className='py-8'
          />
        </CardContent>
      ) : (
        <CardContent className='p-0'>
          <div className='divide-y'>
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
        </CardContent>
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
            <AlertDialogAction variant='destructive' onClick={handleDelete}>Remove</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
