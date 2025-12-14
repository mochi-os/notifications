import { useLayout } from '@mochi/common/context/layout-provider'
import {
  Sidebar,
  SidebarContent,
  SidebarRail,
} from '@mochi/common/components/ui/sidebar'
import { sidebarData } from './data/sidebar-data'
import { NavGroup } from '@mochi/common/components/layout/nav-group'

export function AppSidebar() {
  const { collapsible, variant } = useLayout()
  return (
    <Sidebar collapsible={collapsible} variant={variant}>
      <SidebarContent className="pt-6">
        {sidebarData.navGroups.map((navGroup) => (
          <NavGroup key={navGroup.title} {...navGroup} />
        ))}
      </SidebarContent>
      <SidebarRail />
    </Sidebar>
  )
}
