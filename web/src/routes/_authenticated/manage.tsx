import { useState } from 'react'
import { createFileRoute } from '@tanstack/react-router'
import { ListChecks, Rss } from 'lucide-react'
import { Button, usePageTitle, PageHeader, Main } from '@mochi/common'
import { Card } from '@mochi/common/components/ui/card'
import { SubscriptionsManager } from '@/components/subscriptions-manager'
import { RssDialog } from '@/components/rss-dialog'

export const Route = createFileRoute('/_authenticated/manage')({
  component: ManageNotifications,
})

function ManageNotifications() {
  usePageTitle('Manage notifications')
  const [rssOpen, setRssOpen] = useState(false)

  return (
    <>
      <PageHeader
        title='Manage notifications'
        icon={<ListChecks className='size-4 md:size-5' />}
        actions={
          <Button onClick={() => setRssOpen(true)}>
            <Rss className='size-4' />
            RSS feeds
          </Button>
        }
      />
      <Main>
        <div className='mx-auto max-w-2xl'>
          <Card>
            <SubscriptionsManager />
          </Card>
        </div>
      </Main>

      <RssDialog open={rssOpen} onOpenChange={setRssOpen} initialView='list' />
    </>
  )
}
