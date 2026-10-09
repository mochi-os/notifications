// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { useNotificationCategoryPicker } from '@mochi/web'
import { notificationsApi } from '@/api/notifications'

/**
 * Supplies the shared category picker from this app's own actions: lib/web
 * cannot read the notifications service on an app's behalf.
 */
export function useNotificationCategories() {
  return useNotificationCategoryPicker({
    listCategories: notificationsApi.listCategories,
    lookupTopic: notificationsApi.lookupTopic,
    setTopicCategory: notificationsApi.setTopicCategory,
  })
}
