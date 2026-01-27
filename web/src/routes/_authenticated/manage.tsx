import { useState } from 'react'
import { createFileRoute } from '@tanstack/react-router'
import { ListChecks, Rss } from 'lucide-react'
import { Button, usePageTitle, PageHeader, Main, Section } from '@mochi/common'
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
          <Button variant='outline' onClick={() => setRssOpen(true)}>
            <Rss className='mr-2 size-4' />
            RSS feeds
          </Button>
        }
      />
      <Main>
        <div className='mx-auto max-w-2xl'>
          <Section 
            title="Channels & Subscriptions" 
            description="Control how and where you receive notifications"
          >
            <SubscriptionsManager />
          </Section>
        </div>
      </Main>

      <RssDialog open={rssOpen} onOpenChange={setRssOpen} initialView='list' />
    </>
  )
}
