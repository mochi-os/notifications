import { defineConfig, mergeConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'
import { tanstackRouter } from '@tanstack/router-plugin/vite'
import createBaseViteConfig from '@mochi/config/vite'

// https://vite.dev/config/
export default defineConfig(() =>
  mergeConfig(
    createBaseViteConfig({
      plugins: [
        tanstackRouter({
          target: 'react',
          autoCodeSplitting: true,
        }),
        tailwindcss(),
      ],
    }),
    {
      base: './',
    }
  )
)
