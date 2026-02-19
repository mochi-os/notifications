import { useState } from 'react'
import { createFileRoute, useNavigate } from '@tanstack/react-router'
import { ListChecks, Rss } from 'lucide-react'
import { Button, usePageTitle, PageHeader, Main } from '@mochi/common'
import { SubscriptionsManager } from '@/components/subscriptions-manager'
import { RssDialog } from '@/components/rss-dialog'

export const Route = createFileRoute('/_authenticated/manage')({
  component: ManageNotifications,
})

function ManageNotifications() {
  const navigate = useNavigate()
  usePageTitle('Manage notifications')
  const [rssOpen, setRssOpen] = useState(false)
  const goBackToNotifications = () => navigate({ to: '/' })

  return (
    <>
      <PageHeader
        title='Manage notifications'
        icon={<ListChecks className='size-4 md:size-5' />}
        back={{ label: 'Back to notifications', onFallback: goBackToNotifications }}
        actions={
          <Button variant='outline' onClick={() => setRssOpen(true)}>
            <Rss className='mr-2 size-4' />
            RSS feeds
          </Button>
        }
      />
      <Main>
        <SubscriptionsManager />
      </Main>

      <RssDialog open={rssOpen} onOpenChange={setRssOpen} initialView='list' />
    </>
  )
}
