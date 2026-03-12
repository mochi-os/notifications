import { createFileRoute } from '@tanstack/react-router'
import { AuthenticatedLayout, useAuthStore } from '@mochi/common'

export const Route = createFileRoute('/_authenticated')({
  beforeLoad: async () => {
    const store = useAuthStore.getState()
    if (!store.isInitialized) {
      await store.initialize()
    }
  },
  component: () => <AuthenticatedLayout />,
})
