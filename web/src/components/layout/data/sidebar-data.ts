import { APP_ROUTES } from '@/config/routes'
import {
  MessagesSquare,
  AudioWaveform,
  Bell,
  Command,
  GalleryVerticalEnd,
  Home,
  UserPlus,
  MessageSquare,
  Newspaper,
  LayoutTemplate,
} from 'lucide-react'
import { type SidebarData } from '../types'

export const sidebarData: SidebarData = {
  user: {
    name: 'satnaing',
    email: 'satnaingdev@gmail.com',
    avatar: '/avatars/shadcn.jpg',
  },
  teams: [
    {
      name: 'Mochi OS',
      logo: Command,
      plan: 'Vite + ShadcnUI',
    },
    {
      name: 'Acme Inc',
      logo: GalleryVerticalEnd,
      plan: 'Enterprise',
    },
    {
      name: 'Acme Corp.',
      logo: AudioWaveform,
      plan: 'Startup',
    },
  ],
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
          title: 'Forums',
          url: APP_ROUTES.FORUMS.HOME,
          icon: MessageSquare,
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
