import { APP_ROUTES } from '@/config/app-routes'
import {
  MessagesSquare,
  Bell,
  Home,
  UserPlus,
  LayoutTemplate,
  Newspaper,
} from 'lucide-react'
import { type SidebarData } from '../types'

export const sidebarData: SidebarData = {
  navGroups: [
    {
      title: 'Apps',
      items: [
        {
          title: 'Home',
          url: APP_ROUTES.HOME.HOME,
          icon: Home,
          external: true,
        },
        {
          title: 'Chat',
          url: APP_ROUTES.CHAT.HOME,
          icon: MessagesSquare,
          external: true,
        },
        {
          title: 'Friends',
          url: APP_ROUTES.FRIENDS.HOME,
          icon: UserPlus,
          external: true,
        },
        {
          title: 'Notifications',
          url: APP_ROUTES.NOTIFICATIONS.HOME,
          icon: Bell,
        },
        {
          title: 'Feeds',
          url: APP_ROUTES.FEEDS.HOME,
          icon: Newspaper,
          external: true,
        },
        {
          title: 'Template',
          url: APP_ROUTES.TEMPLATE.HOME,
          icon: LayoutTemplate,
          external: true,
        },
      ],
    },
  ],
}
