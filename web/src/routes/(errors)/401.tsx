import { createFileRoute } from '@tanstack/react-router'
import { UnauthorisedError } from '@mochi/common/features/errors/unauthorized-error'

export const Route = createFileRoute('/(errors)/401')({
  component: UnauthorisedError,
})
