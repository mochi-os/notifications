import { useState } from 'react'
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
  Switch,
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
  getAppPath,
} from '@mochi/common'
import {
  Loader2,
  Copy,
  Check,
  Plus,
  Trash2,
  Rss,
  Pencil,
} from 'lucide-react'

interface RssFeed {
  id: string
  name: string
  token: string
  created: number
  enabled: number
}

type DialogView = 'list' | 'create' | 'created'

interface RssDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  initialView?: DialogView
}

export function RssDialog({ open, onOpenChange, initialView = 'list' }: RssDialogProps) {
  const [view, setView] = useState<DialogView>(initialView)
  const [copied, setCopied] = useState(false)
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const [newFeedName, setNewFeedName] = useState('')
  const [addToExisting, setAddToExisting] = useState(true)
  const [createdFeed, setCreatedFeed] = useState<RssFeed | null>(null)
  const [deleteId, setDeleteId] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingName, setEditingName] = useState('')
  const queryClient = useQueryClient()

  const buildRssUrl = (token: string) => {
    return `${window.location.origin}${getAppPath()}/-/rss?token=${token}`
  }

  const { data: feedsData, isLoading } = useQuery({
    queryKey: ['rss-feeds'],
    queryFn: async () => {
      const result = await requestHelpers.get<RssFeed[]>('-/rss/list')
      console.log('rss/list response:', result, 'isArray:', Array.isArray(result))
      return result
    },
    enabled: open,
  })
  const feeds = Array.isArray(feedsData) ? feedsData : []

  const createMutation = useMutation({
    mutationFn: async ({ name, addToExisting }: { name: string; addToExisting: boolean }) => {
      return await requestHelpers.post<RssFeed>('-/rss/create', { name, add_to_existing: addToExisting ? '1' : '0' })
    },
    onSuccess: (feed) => {
      setCreatedFeed(feed)
      setNewFeedName('')
      setView('created')
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
      queryClient.invalidateQueries({ queryKey: ['destinations', getAppPath()] })
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to create feed'))
    },
  })

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      await requestHelpers.post('-/rss/delete', { id })
    },
    onSuccess: () => {
      toast.success('Feed deleted')
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
      queryClient.invalidateQueries({ queryKey: ['destinations', getAppPath()] })
      setDeleteId(null)
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to delete feed'))
    },
  })

  const renameMutation = useMutation({
    mutationFn: async ({ id, name }: { id: string; name: string }) => {
      await requestHelpers.post('-/rss/rename', { id, name })
    },
    onSuccess: () => {
      toast.success('Feed renamed')
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
      setEditingId(null)
      setEditingName('')
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to rename feed'))
    },
  })

  const toggleEnabledMutation = useMutation({
    mutationFn: async ({ id, enabled }: { id: string; enabled: boolean }) => {
      await requestHelpers.post('-/rss/update', { id, enabled: enabled ? '1' : '0' })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rss-feeds'] })
    },
    onError: (error) => {
      toast.error(getErrorMessage(error, 'Failed to update feed'))
    },
  })

  const handleCopy = (token: string) => {
    navigator.clipboard.writeText(buildRssUrl(token))
    setCopied(true)
    toast.success('Copied to clipboard')
    setTimeout(() => setCopied(false), 2000)
  }

  const handleCopyFeed = (feed: RssFeed) => {
    navigator.clipboard.writeText(buildRssUrl(feed.token))
    setCopiedId(feed.id)
    toast.success('Copied to clipboard')
    setTimeout(() => setCopiedId(null), 2000)
  }

  const handleCreate = () => {
    const name = newFeedName.trim() || 'RSS feed'
    createMutation.mutate({ name, addToExisting })
  }

  const handleStartEdit = (feed: RssFeed) => {
    setEditingId(feed.id)
    setEditingName(feed.name)
  }

  const handleSaveEdit = () => {
    if (!editingId) return
    const name = editingName.trim()
    if (!name) {
      setEditingId(null)
      setEditingName('')
      return
    }
    renameMutation.mutate({ id: editingId, name })
  }

  const handleCancelEdit = () => {
    setEditingId(null)
    setEditingName('')
  }

  const handleClose = () => {
    onOpenChange(false)
    // Reset state after close animation
    setTimeout(() => {
      setView(initialView)
      setNewFeedName('')
      setAddToExisting(true)
      setCreatedFeed(null)
      setCopied(false)
      setCopiedId(null)
      setEditingId(null)
      setEditingName('')
    }, 200)
  }

  return (
    <>
      <Dialog open={open} onOpenChange={handleClose}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {view === 'create' && 'Create RSS feed'}
              {view === 'created' && 'Feed created'}
              {view === 'list' && 'RSS feeds'}
            </DialogTitle>
            {view === 'created' && (
              <DialogDescription>
                Save this URL now. You won't be able to see the token again.
              </DialogDescription>
            )}
          </DialogHeader>

          {view === 'list' && (
            <div className="space-y-4">
              {isLoading ? (
                <div className="space-y-2">
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              ) : feeds.length === 0 ? (
                <div className="text-center py-4">
                  <Rss className="h-8 w-8 mx-auto mb-2 text-muted-foreground" />
                  <p className="text-sm text-muted-foreground">
                    No RSS feeds yet. Create one to get started.
                  </p>
                </div>
              ) : (
                <div className="space-y-3 max-h-72 overflow-y-auto">
                  {feeds.map((feed) => (
                    <div key={feed.id} className="rounded-md border p-3">
                      {editingId === feed.id ? (
                        <div className="flex items-center gap-2">
                          <Input
                            value={editingName}
                            onChange={(e) => setEditingName(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') handleSaveEdit()
                              if (e.key === 'Escape') handleCancelEdit()
                            }}
                            className="flex-1"
                            autoFocus
                          />
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={handleSaveEdit}
                            disabled={renameMutation.isPending}
                          >
                            {renameMutation.isPending ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              <Check className="h-4 w-4" />
                            )}
                          </Button>
                        </div>
                      ) : (
                        <div className="space-y-2">
                          <div className="flex items-center gap-2">
                            <p className="min-w-0 flex-1 font-medium truncate">
                              {feed.name}
                            </p>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => handleCopyFeed(feed)}
                            >
                              {copiedId === feed.id ? (
                                <Check className="h-4 w-4" />
                              ) : (
                                <Copy className="h-4 w-4" />
                              )}
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => handleStartEdit(feed)}
                            >
                              <Pencil className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setDeleteId(feed.id)}
                              disabled={deleteMutation.isPending}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </div>
                          <div className="flex items-center justify-end gap-2">
                            <span className="text-sm text-muted-foreground">
                              Notify by default
                            </span>
                            <Switch
                              checked={feed.enabled === 1}
                              onCheckedChange={(checked) =>
                                toggleEnabledMutation.mutate({ id: feed.id, enabled: checked })
                              }
                              aria-label="Notify by default"
                            />
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
              <DialogFooter>
                <Button onClick={() => setView('create')}>
                  <Plus className="h-4 w-4" />
                  Create feed
                </Button>
              </DialogFooter>
            </div>
          )}

          {view === 'create' && (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="feed-name">Feed name</Label>
                <Input
                  id="feed-name"
                  placeholder="e.g., Feedly, NewsBlur"
                  value={newFeedName}
                  onChange={(e) => setNewFeedName(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleCreate()
                  }}
                />
              </div>
              <div className="flex items-center justify-between rounded-lg border p-4">
                <div>
                  <div className="font-medium">Add to existing subscriptions</div>
                  <div className="text-sm text-muted-foreground">
                    Use this feed for your current notification subscriptions
                  </div>
                </div>
                <Switch
                  checked={addToExisting}
                  onCheckedChange={setAddToExisting}
                />
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={handleClose}>
                  Cancel
                </Button>
                <Button onClick={handleCreate} disabled={createMutation.isPending}>
                  {createMutation.isPending ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Plus className="h-4 w-4" />
                  )}
                  Create feed
                </Button>
              </DialogFooter>
            </div>
          )}

          {view === 'created' && createdFeed && (
            <div className="space-y-4">
              <div className="bg-muted flex items-center gap-2 rounded-md p-3 font-mono text-sm">
                <code className="flex-1 break-all select-all">
                  {buildRssUrl(createdFeed.token)}
                </code>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleCopy(createdFeed.token)}
                  className="shrink-0"
                >
                  {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              </div>
              <DialogFooter>
                <Button variant='outline' onClick={() => setView('list')}>Done</Button>
              </DialogFooter>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete feed?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete this feed. Any RSS readers using it will
              no longer be able to access your notifications.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant='destructive'
              onClick={() => deleteId && deleteMutation.mutate(deleteId)}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
