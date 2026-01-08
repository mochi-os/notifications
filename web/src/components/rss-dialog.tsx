import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
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
} from '@mochi/common'
import {
  Loader2,
  Copy,
  Check,
  Plus,
  Trash2,
  ArrowLeft,
  Key,
} from 'lucide-react'

interface TokenGetResponse {
  exists: boolean
  count?: number
  token?: string
}

interface TokenCreateResponse {
  token: string
}

interface Token {
  hash: string
  name: string
  created: number
  used: number
  expires: number
}

interface TokenListResponse {
  tokens: Token[]
}

function formatDate(timestamp: number): string {
  if (!timestamp) return 'Never'
  return new Date(timestamp * 1000).toLocaleDateString()
}

type DialogView = 'loading' | 'rss' | 'existing' | 'manage' | 'create'

interface RssDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function RssDialog({ open, onOpenChange }: RssDialogProps) {
  const [view, setView] = useState<DialogView>('loading')
  const [rssUrl, setRssUrl] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [newTokenName, setNewTokenName] = useState('')
  const [newToken, setNewToken] = useState<string | null>(null)
  const [deleteHash, setDeleteHash] = useState<string | null>(null)
  const queryClient = useQueryClient()

  const buildRssUrl = (token: string) => {
    return `${window.location.origin}/notifications/rss?token=${token}`
  }

  // Fetch token status when dialog opens
  useEffect(() => {
    if (!open) {
      // Reset state when closing
      setView('loading')
      setRssUrl(null)
      setCopied(false)
      setNewTokenName('')
      setNewToken(null)
      return
    }

    // Fetch token status on open
    const fetchTokenStatus = async () => {
      setView('loading')
      try {
        const response = await requestHelpers.post<TokenGetResponse>('token/get', {
          name: 'RSS feed',
        })
        if (response.exists) {
          setView('existing')
        } else if (response.token) {
          setRssUrl(buildRssUrl(response.token))
          setView('rss')
        }
      } catch (error) {
        toast.error(getErrorMessage(error, 'Failed to get token'))
        onOpenChange(false)
      }
    }

    fetchTokenStatus()
  }, [open, onOpenChange])

  const { data: tokensData, isLoading: tokensLoading } = useQuery({
    queryKey: ['rss-tokens'],
    queryFn: async () => {
      return await requestHelpers.get<TokenListResponse>('token/list')
    },
    enabled: open && view === 'manage',
  })

  const createMutation = useMutation({
    mutationFn: async (name: string) => {
      return await requestHelpers.post<TokenCreateResponse>('token/create', { name })
    },
    onSuccess: (data) => {
      setNewToken(data.token)
      setNewTokenName('')
      queryClient.invalidateQueries({ queryKey: ['rss-tokens'] })
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to create token'))
    },
  })

  const deleteMutation = useMutation({
    mutationFn: async (hash: string) => {
      await requestHelpers.post('token/delete', { hash })
    },
    onSuccess: () => {
      toast.success('Token deleted')
      queryClient.invalidateQueries({ queryKey: ['rss-tokens'] })
      setDeleteHash(null)
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to delete token'))
    },
  })

  const handleCopy = () => {
    if (rssUrl) {
      navigator.clipboard.writeText(rssUrl)
      setCopied(true)
      toast.success('Copied to clipboard')
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleCopyNewToken = () => {
    if (newToken) {
      navigator.clipboard.writeText(buildRssUrl(newToken))
      setCopied(true)
      toast.success('Copied to clipboard')
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleCreate = () => {
    if (!newTokenName.trim()) {
      toast.error('Please enter a token name')
      return
    }
    createMutation.mutate(newTokenName.trim())
  }

  const tokens = tokensData?.tokens || []

  const getTitle = () => {
    switch (view) {
      case 'manage':
        return 'Manage tokens'
      case 'create':
        return newToken ? 'Token created' : 'Create token'
      default:
        return 'RSS feed'
    }
  }

  const getDescription = () => {
    switch (view) {
      case 'existing':
        return 'You already have authentication tokens. If you have previously set up this RSS feed, your existing URL will work.'
      case 'manage':
        return null
      case 'create':
        return newToken
          ? "Save this URL now. You won't be able to see it again."
          : 'Create a new authentication token.'
      default:
        return 'Add this URL to your RSS reader.'
    }
  }

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{getTitle()}</DialogTitle>
            {getDescription() && (
              <DialogDescription>{getDescription()}</DialogDescription>
            )}
          </DialogHeader>

          {view === 'loading' && (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin" />
            </div>
          )}

          {view === 'rss' && rssUrl && (
            <div className="space-y-4">
              <div className="bg-muted flex items-center gap-2 rounded-md p-3 font-mono text-sm">
                <code className="flex-1 break-all select-all">{rssUrl}</code>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleCopy}
                  className="shrink-0"
                >
                  {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              </div>
              <p className="text-sm text-muted-foreground">
                Save this URL securely. You won't be able to see it again.
              </p>
              <DialogFooter>
                <Button onClick={() => onOpenChange(false)}>Done</Button>
              </DialogFooter>
            </div>
          )}

          {view === 'existing' && (
            <div className="space-y-4">
              <div className="bg-muted rounded-md p-3 font-mono text-sm">
                <code className="break-all select-all">
                  {window.location.origin}/notifications/rss?token=...
                </code>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setView('manage')}>
                  <Key className="h-4 w-4" />
                  Manage tokens
                </Button>
              </DialogFooter>
            </div>
          )}

          {view === 'manage' && (
            <div className="space-y-4">
              {tokensLoading ? (
                <div className="space-y-2">
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              ) : tokens.length === 0 ? (
                <p className="text-sm text-muted-foreground py-4 text-center">
                  No tokens yet.
                </p>
              ) : (
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  {tokens.map((token) => (
                    <div
                      key={token.hash}
                      className="flex items-center justify-between p-3 rounded-md border"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="font-medium truncate">{token.name}</p>
                        <p className="text-xs text-muted-foreground">
                          Created {formatDate(token.created)}
                          {token.used ? ` · Last used ${formatDate(token.used)}` : ''}
                        </p>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setDeleteHash(token.hash)}
                        disabled={deleteMutation.isPending}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
              <DialogFooter className="flex-row gap-2 sm:justify-between">
                <Button variant="ghost" onClick={() => setView('existing')}>
                  <ArrowLeft className="h-4 w-4" />
                  Back
                </Button>
                <Button onClick={() => setView('create')}>
                  <Plus className="h-4 w-4" />
                  Create token
                </Button>
              </DialogFooter>
            </div>
          )}

          {view === 'create' && (
            <div className="space-y-4">
              {newToken ? (
                <>
                  <div className="bg-muted flex items-center gap-2 rounded-md p-3 font-mono text-sm">
                    <code className="flex-1 break-all select-all">
                      {buildRssUrl(newToken)}
                    </code>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={handleCopyNewToken}
                      className="shrink-0"
                    >
                      {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                    </Button>
                  </div>
                  <p className="text-sm text-muted-foreground">
                    Save this URL securely. You won't be able to see it again.
                  </p>
                  <DialogFooter>
                    <Button
                      onClick={() => {
                        setNewToken(null)
                        setView('manage')
                      }}
                    >
                      Done
                    </Button>
                  </DialogFooter>
                </>
              ) : (
                <>
                  <div className="space-y-2">
                    <Label htmlFor="token-name">Token name</Label>
                    <Input
                      id="token-name"
                      placeholder="e.g., Feedly"
                      value={newTokenName}
                      onChange={(e) => setNewTokenName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleCreate()
                      }}
                    />
                  </div>
                  <DialogFooter className="flex-row gap-2 sm:justify-between">
                    <Button variant="ghost" onClick={() => setView('manage')}>
                      <ArrowLeft className="h-4 w-4" />
                      Back
                    </Button>
                    <Button onClick={handleCreate} disabled={createMutation.isPending}>
                      {createMutation.isPending && (
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

      <AlertDialog open={!!deleteHash} onOpenChange={() => setDeleteHash(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete token?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete this token. Any RSS readers using it will
              no longer be able to access your feed.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => deleteHash && deleteMutation.mutate(deleteHash)}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
