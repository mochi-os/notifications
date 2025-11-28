import { StrictMode } from 'react'
import ReactDOM from 'react-dom/client'
import { AxiosError } from 'axios'
import {
  QueryCache,
  QueryClient,
  QueryClientProvider,
} from '@tanstack/react-query'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import { handleServerError } from '@/lib/handle-server-error'
import { env } from '@mochi/config/env'
// import { DirectionProvider } from './context/direction-provider' // Commented for future use (RTL support)
// import { FontProvider } from './context/font-provider' // Commented for future use (Font switching)
import { ThemeProvider } from './context/theme-provider'
// Generated Routes
import { routeTree } from './routeTree.gen'
// Styles
import './styles/index.css'

const isProduction = env.appEnv === 'production'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (failureCount, error) => {
        // eslint-disable-next-line no-console
        if (env.debug) console.log({ failureCount, error })

        if (failureCount >= 0 && env.debug) return false
        if (failureCount > 3 && isProduction) return false

        return !(
          error instanceof AxiosError &&
          [401, 403].includes(error.response?.status ?? 0)
        )
      },
      refetchOnWindowFocus: isProduction,
      staleTime: 10 * 1000, // 10s
    },
    mutations: {
      onError: (error) => {
        handleServerError(error)

        if (error instanceof AxiosError) {
          if (error.response?.status === 304) {
            toast.error('Content not modified!')
          }
        }
      },
    },
  },
  queryCache: new QueryCache({
    onError: (error) => {
      if (error instanceof AxiosError) {
        // 401 is handled centrally in the API client interceptor
        if (error.response?.status === 500) {
          toast.error('Internal Server Error!')
          router.navigate({ to: '/500' })
        }
        if (error.response?.status === 403) {
          // router.navigate("/forbidden", { replace: true });
        }
      }
    },
  }),
})

const getBasepath = () => {
  const pathname = window.location.pathname;
  // Extract basepath: /chat/ -> /chat/, /chat/some-route -> /chat/
  // Match pattern: /<app-name>/ (with trailing slash)
  const match = pathname.match(/^(\/[^/]+\/)/);
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
