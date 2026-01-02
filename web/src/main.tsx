import { StrictMode } from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { useAuthStore, ThemeProvider, createQueryClient } from '@mochi/common'
// Generated Routes
import { routeTree } from './routeTree.gen'
// Styles
import './styles/index.css'

const queryClient = createQueryClient({
  onServerError: () => router.navigate({ to: '/500' }),
})

const getBasepath = () => {
  const pathname = window.location.pathname;
  // Extract basepath: /chat/ -> /chat/, /chat/some-route -> /chat/
  // Match pattern: /<app-name>/ (with trailing slash)
  const match = pathname.match(/^(\/[^/]+)/);
  return match ? match[1] : '/';
};

const router = createRouter({
  routeTree,
  context: { queryClient },
  basepath: getBasepath(),
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
useAuthStore.getState().initialize()

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
