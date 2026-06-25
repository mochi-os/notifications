// Copyright © 2026 Mochi OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { useState, useEffect, useRef } from 'react'
import { Trans, useLingui } from '@lingui/react/macro'
import {
  Button,
  ConfirmDialog,
  ResponsiveDialog,
  ResponsiveDialogContent,
  ResponsiveDialogDescription,
  ResponsiveDialogFooter,
  ResponsiveDialogHeader,
  ResponsiveDialogTitle,
  Input,
  Label,
  Switch,
  EmptyState,
  GeneralError,
  ListSkeleton,
  getErrorMessage,
  toast,
  toastAction,
  getAppPath,
  requestHelpers,
  useQueryWithError,
  shellClipboardWrite,
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from '@mochi/web'
import { Loader2, Copy, Check, Plus, Trash2, Rss, Pencil } from 'lucide-react'
import {
  type RssFeed,
  useCreateRssFeedMutation,
  useDeleteRssFeedMutation,
  useRenameRssFeedMutation,
  useToggleRssFeedEnabledMutation,
} from '@/hooks/useRssFeeds'

type DialogView = 'list' | 'create' | 'created'

interface RssDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  initialView?: DialogView
}

export function RssDialog({
  open,
  onOpenChange,
  initialView = 'list',
}: RssDialogProps) {
  const { t } = useLingui()
  const [view, setView] = useState<DialogView>(initialView)
  const [copied, setCopied] = useState(false)
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const [newFeedName, setNewFeedName] = useState('')
  const [addToExisting, setAddToExisting] = useState(true)
  const [createdFeed, setCreatedFeed] = useState<RssFeed | null>(null)
  const [deleteId, setDeleteId] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingName, setEditingName] = useState('')

  const createMutation = useCreateRssFeedMutation()
  const deleteMutation = useDeleteRssFeedMutation()
  const renameMutation = useRenameRssFeedMutation()
  const toggleEnabledMutation = useToggleRssFeedEnabledMutation()

  const copiedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const copiedIdTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Clean up copy timers on unmount
  useEffect(() => {
    return () => {
      if (copiedTimerRef.current) clearTimeout(copiedTimerRef.current)
      if (copiedIdTimerRef.current) clearTimeout(copiedIdTimerRef.current)
    }
  }, [])

  // Reset dialog state after close animation completes
  useEffect(() => {
    if (!open) {
      const timer = setTimeout(() => {
        setView(initialView)
        setNewFeedName('')
        setAddToExisting(true)
        setCreatedFeed(null)
        setCopied(false)
        setCopiedId(null)
        setEditingId(null)
        setEditingName('')
      }, 200)
      return () => clearTimeout(timer)
    }
  }, [open, initialView])

  const buildRssUrl = (token: string) => {
    return `${window.location.origin}${getAppPath()}/-/rss?token=${token}`
  }

  const {
    data: feedsData,
    isLoading,
    isError,
    error,
    refetch,
  } = useQueryWithError({
    queryKey: ['rss-feeds'],
    queryFn: async () => {
      return await requestHelpers.get<RssFeed[]>('-/rss/list')
    },
    enabled: open,
  })
  const feeds = Array.isArray(feedsData) ? feedsData : []

  const handleCopy = async (token: string) => {
    const ok = await shellClipboardWrite(buildRssUrl(token))
    if (!ok) return
    setCopied(true)
    toast.success(t`Copied to clipboard`)
    if (copiedTimerRef.current) clearTimeout(copiedTimerRef.current)
    copiedTimerRef.current = setTimeout(() => setCopied(false), 2000)
  }

  const handleCopyFeed = async (feed: RssFeed) => {
    const ok = await shellClipboardWrite(buildRssUrl(feed.token))
    if (!ok) return
    setCopiedId(feed.id)
    toast.success(t`Copied to clipboard`)
    if (copiedIdTimerRef.current) clearTimeout(copiedIdTimerRef.current)
    copiedIdTimerRef.current = setTimeout(() => setCopiedId(null), 2000)
  }

  const handleCreate = async () => {
    const name = newFeedName.trim() || t`RSS feed`
    try {
      const feed = await toastAction(
        createMutation.mutateAsync({ name, addToExisting }),
        {
          loading: t`Creating RSS feed...`,
          success: false,
          error: (err) => getErrorMessage(err, t`Failed to create RSS feed`),
        }
      )
      setCreatedFeed(feed)
      setNewFeedName('')
      setView('created')
    } catch {
      // toastAction already showed error
    }
  }

  const handleStartEdit = (feed: RssFeed) => {
    setEditingId(feed.id)
    setEditingName(feed.name)
  }

  const handleSaveEdit = async () => {
    if (!editingId) return
    const name = editingName.trim()
    if (!name) {
      setEditingId(null)
      setEditingName('')
      return
    }
    try {
      await toastAction(renameMutation.mutateAsync({ id: editingId, name }), {
        loading: t`Saving...`,
        success: t`Feed renamed`,
        error: (err) => getErrorMessage(err, t`Failed to rename feed`),
      })
      setEditingId(null)
      setEditingName('')
    } catch {
      // toastAction already showed error
    }
  }

  const handleCancelEdit = () => {
    setEditingId(null)
    setEditingName('')
  }

  const handleDelete = async () => {
    if (!deleteId) return
    try {
      await toastAction(deleteMutation.mutateAsync(deleteId), {
        loading: t`Deleting feed...`,
        success: t`Feed deleted`,
        error: (err) => getErrorMessage(err, t`Failed to delete feed`),
      })
      setDeleteId(null)
    } catch {
      // toastAction already showed error
    }
  }

  const handleToggleEnabled = async (id: string, enabled: boolean) => {
    try {
      await toastAction(
        toggleEnabledMutation.mutateAsync({ id, enabled }),
        {
          loading: t`Saving...`,
          success: false,
          error: (err) => getErrorMessage(err, t`Failed to update feed`),
        }
      )
    } catch {
      // toastAction already showed error
    }
  }

  const handleClose = () => {
    onOpenChange(false)
    // State reset is handled by the useEffect watching `open`
  }

  return (
    <>
      <ResponsiveDialog open={open} onOpenChange={handleClose}>
        <ResponsiveDialogContent>
          <ResponsiveDialogHeader>
            <ResponsiveDialogTitle>
              {view === 'create' && <Trans>Create RSS feed</Trans>}
              {view === 'created' && <Trans>Feed created</Trans>}
              {view === 'list' && <Trans>RSS feeds</Trans>}
            </ResponsiveDialogTitle>
            {view === 'created' && (
              <ResponsiveDialogDescription>
                <Trans>Save this URL now. You won't be able to see the token again.</Trans>
              </ResponsiveDialogDescription>
            )}
          </ResponsiveDialogHeader>

          {view === 'list' && (
            <div className='space-y-4'>
              {isLoading ? (
                <ListSkeleton variant='simple' height='h-12' count={2} />
              ) : isError ? (
                <GeneralError
                  error={error}
                  minimal
                  mode='inline'
                  reset={() => void refetch()}
                  className='py-4'
                />
              ) : feeds.length === 0 ? (
                <EmptyState
                  icon={Rss}
                  title={t`No RSS feeds yet`}
                  description={t`Create one to get started.`}
                  className='py-4'
                />
              ) : (
                <div className='max-h-72 space-y-3 overflow-y-auto'>
                  {feeds.map((feed) => (
                    <div key={feed.id} className='rounded-md border p-3'>
                      {editingId === feed.id ? (
                        <div className='flex items-center gap-2'>
                          <Input
                            value={editingName}
                            onChange={(e) => setEditingName(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') handleSaveEdit()
                              if (e.key === 'Escape') handleCancelEdit()
                            }}
                            className='flex-1'
                            autoFocus
                          />
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Button
                                variant='ghost'
                                size='sm'
                                onClick={handleSaveEdit}
                                disabled={renameMutation.isPending}
                                aria-label={t`Save`}
                              >
                                {renameMutation.isPending ? (
                                  <Loader2 className='h-4 w-4 animate-spin' />
                                ) : (
                                  <Check className='h-4 w-4' />
                                )}
                              </Button>
                            </TooltipTrigger>
                            <TooltipContent>{t`Save`}</TooltipContent>
                          </Tooltip>
                        </div>
                      ) : (
                        <div className='space-y-2'>
                          <div className='flex items-center gap-2'>
                            <p className='min-w-0 flex-1 truncate font-medium'>
                              {feed.name}
                            </p>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <Button
                                  variant='ghost'
                                  size='sm'
                                  onClick={() => handleCopyFeed(feed)}
                                  aria-label={t`Copy`}
                                >
                                  {copiedId === feed.id ? (
                                    <Check className='h-4 w-4' />
                                  ) : (
                                    <Copy className='h-4 w-4' />
                                  )}
                                </Button>
                              </TooltipTrigger>
                              <TooltipContent>{t`Copy`}</TooltipContent>
                            </Tooltip>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <Button
                                  variant='ghost'
                                  size='sm'
                                  onClick={() => handleStartEdit(feed)}
                                  aria-label={t`Edit feed`}
                                >
                                  <Pencil className='h-4 w-4' />
                                </Button>
                              </TooltipTrigger>
                              <TooltipContent>{t`Edit feed`}</TooltipContent>
                            </Tooltip>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <Button
                                  variant='ghost'
                                  size='sm'
                                  onClick={() => setDeleteId(feed.id)}
                                  disabled={deleteMutation.isPending}
                                  aria-label={t`Delete feed`}
                                >
                                  <Trash2 className='h-4 w-4' />
                                </Button>
                              </TooltipTrigger>
                              <TooltipContent>{t`Delete feed`}</TooltipContent>
                            </Tooltip>
                          </div>
                          <div className='flex items-center justify-end gap-2'>
                            <span className='text-muted-foreground text-sm'>
                              <Trans>Notify by default</Trans>
                            </span>
                            <Switch
                              checked={feed.enabled === 1}
                              onCheckedChange={(checked) =>
                                void handleToggleEnabled(feed.id, checked)
                              }
                              aria-label={t`Notify by default`}
                            />
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
              <ResponsiveDialogFooter>
                <Button onClick={() => setView('create')}>
                  <Plus className='h-4 w-4' />
                  <Trans>Create feed</Trans>
                </Button>
              </ResponsiveDialogFooter>
            </div>
          )}

          {view === 'create' && (
            <div className='space-y-4'>
              <div className='space-y-2'>
                <Label htmlFor='feed-name'><Trans>Feed name</Trans></Label>
                <Input
                  id='feed-name'
                  placeholder={t`e.g., Feedly, NewsBlur`}
                  value={newFeedName}
                  onChange={(e) => setNewFeedName(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleCreate()
                  }}
                />
              </div>
              <div className='flex items-center justify-between rounded-lg border p-4'>
                <div>
                  <div className='font-medium'>
                    <Trans>Add to existing subscriptions</Trans>
                  </div>
                  <div className='text-muted-foreground text-sm'>
                    <Trans>Use this feed for your current notification subscriptions</Trans>
                  </div>
                </div>
                <Switch
                  checked={addToExisting}
                  onCheckedChange={setAddToExisting}
                />
              </div>
              <ResponsiveDialogFooter>
                <Button variant='outline' onClick={handleClose}>
                  <Trans>Cancel</Trans>
                </Button>
                <Button
                  onClick={handleCreate}
                  disabled={createMutation.isPending}
                >
                  {createMutation.isPending ? (
                    <Loader2 className='h-4 w-4 animate-spin' />
                  ) : (
                    <Plus className='h-4 w-4' />
                  )}
                  <Trans>Create feed</Trans>
                </Button>
              </ResponsiveDialogFooter>
            </div>
          )}

          {view === 'created' && createdFeed && (
            <div className='space-y-4'>
              <div className='bg-muted flex items-center gap-2 rounded-md p-3 font-mono text-sm'>
                <code className='flex-1 break-all select-all'>
                  {buildRssUrl(createdFeed.token)}
                </code>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant='ghost'
                      size='sm'
                      onClick={() => handleCopy(createdFeed.token)}
                      className='shrink-0'
                      aria-label={t`Copy`}
                    >
                      {copied ? (
                        <Check className='h-4 w-4' />
                      ) : (
                        <Copy className='h-4 w-4' />
                      )}
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>{t`Copy`}</TooltipContent>
                </Tooltip>
              </div>
              <ResponsiveDialogFooter>
                <Button variant='outline' onClick={() => setView('list')}>
                  <Trans>Done</Trans>
                </Button>
              </ResponsiveDialogFooter>
            </div>
          )}
        </ResponsiveDialogContent>
      </ResponsiveDialog>

      <ConfirmDialog
        open={!!deleteId}
        onOpenChange={(isOpen) => {
          if (!isOpen) setDeleteId(null)
        }}
        title={t`Delete Feed?`}
        desc={t`This will permanently delete this feed. Any RSS readers using it will no longer be able to access your notifications.`}
        confirmText={t`Delete`}
        destructive
        handleConfirm={() => {
          void handleDelete()
        }}
        isLoading={deleteMutation.isPending}
      />
    </>
  )
}
