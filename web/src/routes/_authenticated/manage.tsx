import { useState } from 'react'
import { createFileRoute } from '@tanstack/react-router'
import { Rss } from 'lucide-react'
import { Button } from '@mochi/common/components/ui/button'
import { SubscriptionsManager } from '@/components/subscriptions-manager'
import { RssDialog } from '@/components/rss-dialog'

export const Route = createFileRoute('/_authenticated/manage')({
  component: ManageNotifications,
})

function ManageNotifications() {
  const [rssOpen, setRssOpen] = useState(false)

  return (
    <main className="container py-6">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold tracking-tight">Manage notifications</h1>
        <Button onClick={() => setRssOpen(true)}>
          <Rss className="h-4 w-4" />
          RSS feeds
        </Button>
      </div>

      <SubscriptionsManager />

      <RssDialog open={rssOpen} onOpenChange={setRssOpen} initialView="list" />
    </main>
  )
}
