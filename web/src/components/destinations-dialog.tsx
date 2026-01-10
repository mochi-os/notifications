import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { SubscriptionsManager } from './subscriptions-manager'
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Input,
  Label,
  getErrorMessage,
  toast,
  Skeleton,
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  requestHelpers,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  useAccounts,
  AccountAdd,
  AccountVerify,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  getProviderLabel,
  type Account,
  type Provider,
} from '@mochi/common'
import {
  Loader2,
  Copy,
  Check,
  Plus,
  Trash2,
  ArrowLeft,
  Rss,
  Bell,
  Mail,
  MoreHorizontal,
  Clock,
  CheckCircle2,
  Webhook,
  ChevronDown,
  ListChecks,
} from 'lucide-react'

interface Feed {
  id: string
  name: string
  token: string
  created: number
}

interface FeedListResponse {
  data: Feed[]
}

interface FeedCreateResponse {
  data: Feed
}

type DialogView = 'list' | 'create-feed' | 'subscriptions'

interface DestinationsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

function getProviderIcon(type: string) {
  switch (type) {
    case 'email':
      return <Mail className="h-4 w-4" />
    case 'browser':
      return <Bell className="h-4 w-4" />
    case 'pushbullet':
      return (
        <svg className="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
          <circle cx="12" cy="12" r="10" />
        </svg>
      )
    case 'url':
      return <Webhook className="h-4 w-4" />
    default:
      return <Bell className="h-4 w-4" />
  }
}

function FeedItem({
  feed,
  onDelete,
  isDeleting,
}: {
  feed: Feed
  onDelete: (id: string) => void
  isDeleting: boolean
}) {
  const [copied, setCopied] = useState(false)

  const buildRssUrl = (token: string) => {
    return `${window.location.origin}/notifications/rss?token=${token}`
  }

  const handleCopy = () => {
    navigator.clipboard.writeText(buildRssUrl(feed.token))
    setCopied(true)
    toast.success('Copied to clipboard')
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="flex items-center justify-between py-3 border-b last:border-0">
      <div className="flex items-center gap-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-muted">
          <Rss className="h-4 w-4" />
        </div>
        <div>
          <div className="flex items-center gap-2">
            <span className="font-medium">{feed.name}</span>
          </div>
          <div className="text-sm text-muted-foreground">RSS feed</div>
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
          <DropdownMenuItem onClick={handleCopy}>
            {copied ? <Check className="mr-2 h-4 w-4" /> : <Copy className="mr-2 h-4 w-4" />}
            Copy URL
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => onDelete(feed.id)}
            className="text-destructive focus:text-destructive"
          >
            <Trash2 className="mr-2 h-4 w-4" />
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  )
}

function AccountItem({
  account,
  providers,
  onRemove,
  onVerify,
  isRemoving,
}: {
  account: Account
  providers: Provider[]
  onRemove: (id: number) => void
  onVerify: (account: Account) => void
  isRemoving: boolean
}) {
  const isVerified = account.verified > 0
  const provider = providers.find((p) => p.type === account.type)
  const needsVerification = provider?.verify && !isVerified

  return (
    <div className="flex items-center justify-between py-3 border-b last:border-0">
      <div className="flex items-center gap-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-muted">
          {getProviderIcon(account.type)}
        </div>
        <div>
          <div className="flex items-center gap-2">
            <span className="font-medium">
              {account.label || getProviderLabel(account.type)}
            </span>
            {needsVerification ? (
              <span className="inline-flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400">
                <Clock className="h-3 w-3" />
                Unverified
              </span>
            ) : isVerified ? (
              <CheckCircle2 className="h-4 w-4 text-green-600 dark:text-green-400" />
            ) : null}
          </div>
          {account.identifier && (
            <div className="text-sm text-muted-foreground">{account.identifier}</div>
          )}
        </div>
      </div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" disabled={isRemoving}>
            {isRemoving ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <MoreHorizontal className="h-4 w-4" />
            )}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {needsVerification && (
            <DropdownMenuItem onClick={() => onVerify(account)}>
              <Mail className="mr-2 h-4 w-4" />
              Verify
            </DropdownMenuItem>
          )}
          <DropdownMenuItem
            onClick={() => onRemove(account.id)}
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

export function DestinationsDialog({ open, onOpenChange }: DestinationsDialogProps) {
  const [view, setView] = useState<DialogView>('list')
  const [newFeedName, setNewFeedName] = useState('')
  const [newFeed, setNewFeed] = useState<Feed | null>(null)
  const [deleteFeedId, setDeleteFeedId] = useState<string | null>(null)
  const [isAddAccountOpen, setIsAddAccountOpen] = useState(false)
  const [verifyAccount, setVerifyAccount] = useState<Account | null>(null)
  const [copied, setCopied] = useState(false)
  const queryClient = useQueryClient()

  const {
    providers,
    accounts,
    isLoading: isAccountsLoading,
    add: addAccount,
    remove: removeAccount,
    verify,
    isAdding,
    isRemoving,
    isVerifying,
  } = useAccounts('/notifications', 'notify')

  const { data: feedsData, isLoading: isFeedsLoading } = useQuery({
    queryKey: ['rss-feeds'],
    queryFn: async () => {
      return await requestHelpers.get<FeedListResponse>('rss/list')
    },
    enabled: open,
  })

  const isLoading = isAccountsLoading || isFeedsLoading
  const feeds = feedsData?.data || []

  useEffect(() => {
    if (!open) {
      setView('list')
      setNewFeedName('')
      setNewFeed(null)
    }
  }, [open])

  const createFeedMutation = useMutation({
    mutationFn: async (name: string) => {
      return await requestHelpers.post<FeedCreateResponse>('rss/create', { name })
    },
    onSuccess: (data) => {
      setNewFeed(data.data)
      setNewFeedName('')
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to create feed'))
    },
  })

  const deleteFeedMutation = useMutation({
    mutationFn: async (id: string) => {
      await requestHelpers.post('rss/delete', { id })
    },
    onSuccess: () => {
      toast.success('Feed deleted')
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
      setDeleteFeedId(null)
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to delete feed'))
    },
  })

  const handleAddAccount = async (type: string, fields: Record<string, string>) => {
    try {
      const account = await addAccount(type, fields)
      toast.success('Account added')
      setIsAddAccountOpen(false)

      const provider = providers.find((p) => p.type === type)
      if (provider?.verify && account.verified === 0) {
        setVerifyAccount(account)
      }
    } catch {
      toast.error('Failed to add account')
    }
  }

  const handleRemoveAccount = async (id: number) => {
    try {
      await removeAccount(id)
      toast.success('Account removed')
    } catch {
      toast.error('Failed to remove account')
    }
  }

  const handleVerify = async (id: number, code: string) => {
    try {
      const result = await verify(id, code)
      if (result) {
        toast.success('Account verified')
        setVerifyAccount(null)
      } else {
        toast.error('Invalid verification code')
      }
    } catch {
      toast.error('Verification failed')
    }
  }

  const handleResend = async (id: number) => {
    try {
      await verify(id)
      toast.success('Verification code sent')
    } catch {
      toast.error('Failed to send verification code')
    }
  }

  const buildRssUrl = (token: string) => {
    return `${window.location.origin}/notifications/rss?token=${token}`
  }

  const handleCopyNewFeed = () => {
    if (newFeed) {
      navigator.clipboard.writeText(buildRssUrl(newFeed.token))
      setCopied(true)
      toast.success('Copied to clipboard')
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleCreateFeed = () => {
    if (!newFeedName.trim()) {
      toast.error('Please enter a feed name')
      return
    }
    createFeedMutation.mutate(newFeedName.trim())
  }

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>
              {view === 'create-feed'
                ? newFeed
                  ? 'Feed created'
                  : 'Create RSS feed'
                : view === 'subscriptions'
                  ? 'Manage subscriptions'
                  : 'Notification destinations'}
            </DialogTitle>
            {view === 'list' && (
              <DialogDescription>Manage where your notifications are sent.</DialogDescription>
            )}
            {view === 'subscriptions' && (
              <DialogDescription>
                Manage which apps can send you notifications.
              </DialogDescription>
            )}
            {view === 'create-feed' && !newFeed && (
              <DialogDescription>
                Create a new RSS feed to receive notifications in your RSS reader.
              </DialogDescription>
            )}
            {view === 'create-feed' && newFeed && (
              <DialogDescription>
                Save this URL now. You won't be able to see it again.
              </DialogDescription>
            )}
          </DialogHeader>

          {view === 'list' && (
            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">Manage destinations</CardTitle>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button size="sm">
                        <Plus className="mr-2 h-4 w-4" />
                        Add
                        <ChevronDown className="ml-2 h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => setIsAddAccountOpen(true)}>
                        <Plus className="mr-2 h-4 w-4" />
                        Connected account
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => setView('create-feed')}>
                        <Rss className="mr-2 h-4 w-4" />
                        RSS feed
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </CardHeader>
              <CardContent>
                {isLoading ? (
                  <div className="space-y-2">
                    <Skeleton className="h-16 w-full" />
                    <Skeleton className="h-16 w-full" />
                  </div>
                ) : accounts.length === 0 && feeds.length === 0 ? (
                  <div className="text-center py-8 text-muted-foreground">
                    <p>No destinations configured</p>
                    <p className="text-sm mt-1">
                      Add a destination to receive notifications outside the browser.
                    </p>
                  </div>
                ) : (
                  <div>
                    {[...accounts]
                      .sort((a, b) => {
                        const aName = a.label || getProviderLabel(a.type)
                        const bName = b.label || getProviderLabel(b.type)
                        const nameCompare = aName.localeCompare(bName)
                        if (nameCompare !== 0) return nameCompare
                        const aType = getProviderLabel(a.type)
                        const bType = getProviderLabel(b.type)
                        return aType.localeCompare(bType)
                      })
                      .map((account) => (
                        <AccountItem
                          key={`account-${account.id}`}
                          account={account}
                          providers={providers}
                          onRemove={handleRemoveAccount}
                          onVerify={setVerifyAccount}
                          isRemoving={isRemoving}
                        />
                      ))}
                    {feeds.map((feed) => (
                      <FeedItem
                        key={`feed-${feed.id}`}
                        feed={feed}
                        onDelete={(id) => setDeleteFeedId(id)}
                        isDeleting={deleteFeedMutation.isPending}
                      />
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {view === 'list' && (
            <Button
              variant="outline"
              className="w-full"
              onClick={() => setView('subscriptions')}
            >
              <ListChecks className="mr-2 h-4 w-4" />
              Manage subscriptions
            </Button>
          )}

          {view === 'subscriptions' && (
            <div className="space-y-4">
              <SubscriptionsManager />
              <DialogFooter>
                <Button variant="outline" onClick={() => setView('list')}>
                  <ArrowLeft className="h-4 w-4" />
                  Back
                </Button>
              </DialogFooter>
            </div>
          )}

          {view === 'create-feed' && (
            <div className="space-y-4">
              {newFeed ? (
                <>
                  <div className="bg-muted flex items-center gap-2 rounded-md p-3 font-mono text-sm">
                    <code className="flex-1 break-all select-all">
                      {buildRssUrl(newFeed.token)}
                    </code>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={handleCopyNewFeed}
                      className="shrink-0"
                    >
                      {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                    </Button>
                  </div>
                  <DialogFooter>
                    <Button
                      onClick={() => {
                        setNewFeed(null)
                        setView('list')
                      }}
                    >
                      Done
                    </Button>
                  </DialogFooter>
                </>
              ) : (
                <>
                  <div className="space-y-2">
                    <Label htmlFor="feed-name">Feed name</Label>
                    <Input
                      id="feed-name"
                      placeholder="e.g., Feedly"
                      value={newFeedName}
                      onChange={(e) => setNewFeedName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleCreateFeed()
                      }}
                    />
                  </div>
                  <DialogFooter className="flex-row gap-2 sm:justify-between">
                    <Button variant="ghost" onClick={() => setView('list')}>
                      <ArrowLeft className="h-4 w-4" />
                      Back
                    </Button>
                    <Button onClick={handleCreateFeed} disabled={createFeedMutation.isPending}>
                      {createFeedMutation.isPending && (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      )}
                      Create
                    </Button>
                  </DialogFooter>
                </>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AccountAdd
        open={isAddAccountOpen}
        onOpenChange={setIsAddAccountOpen}
        providers={providers}
        onAdd={handleAddAccount}
        isAdding={isAdding}
        appBase="/notifications"
      />

      {verifyAccount && (
        <AccountVerify
          open={!!verifyAccount}
          onOpenChange={(open) => !open && setVerifyAccount(null)}
          account={verifyAccount}
          onVerify={handleVerify}
          onResend={handleResend}
          isVerifying={isVerifying}
        />
      )}

      <AlertDialog open={!!deleteFeedId} onOpenChange={() => setDeleteFeedId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete RSS feed?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete this RSS feed. Any RSS readers using it will no longer
              be able to access your notifications.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => deleteFeedId && deleteFeedMutation.mutate(deleteFeedId)}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
