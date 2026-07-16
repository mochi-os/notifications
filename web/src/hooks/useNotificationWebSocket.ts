// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { useNotificationWebSocket as useCommonNotificationWebSocket } from '@mochi/web'

// Compatibility wrapper to keep app-local imports stable while using the common singleton socket manager.
export function useNotificationWebSocket() {
  useCommonNotificationWebSocket()
}
