import { StrictMode } from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { ThemeProvider, createQueryClient, getRouterBasepath } from '@mochi/common'
// Generated Routes
import { routeTree } from './routeTree.gen'
// Styles
import './styles/index.css'

const queryClient = createQueryClient({
  onServerError: () => router.navigate({ to: '/500' }),
})

const router = createRouter({
  routeTree,
  context: { queryClient },
  basepath: getRouterBasepath(),
  defaultPreload: 'intent',
  defaultPreloadStaleTime: 0,
})

// Register the router instance for type safety
declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}

// Initialize auth state from cookie on app start

// Render the app
const rootElement = document.getElementById('root')!
if (!rootElement.innerHTML) {
  const root = ReactDOM.createRoot(rootElement)
  root.render(
    <StrictMode>
      <QueryClientProvider client={queryClient}>
        <ThemeProvider>
          {/* <FontProvider> */}
            {/* <DirectionProvider> */}
              <RouterProvider router={router} />
            {/* </DirectionProvider> */}
          {/* </FontProvider> */}
        </ThemeProvider>
      </QueryClientProvider>
    </StrictMode>
  )
}
