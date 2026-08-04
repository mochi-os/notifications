// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

import { useState } from 'react'
import {
  toast,
  getErrorMessage,
  type NotificationCategory,
  type NotificationTopic,
} from '@mochi/web'
import { useLingui } from '@lingui/react/macro'
import { notificationsApi } from '@/api/notifications'

/**
 * Drives the shared category picker from THIS app's own actions.
 *
 * The picker holds no data and issues no request of its own: lib/web ships
 * inside every app's bundle and cannot read the notifications service on an
 * app's behalf. It used to try, against the menu app's routes with this app's
 * token, which core refuses with app_token_mismatch - so the picker silently
 * never loaded here. This app owns the service, so it supplies the data.
 *
 * Only one picker is open at a time, so a single slot of state serves every row.
 */
export function useNotificationCategories() {
  const { t } = useLingui()
  const [openKey, setOpenKey] = useState<string | null>(null)
  const [categories, setCategories] = useState<NotificationCategory[] | null>(null)
  const [topic, setTopic] = useState<NotificationTopic | null>(null)
  const [saving, setSaving] = useState(false)

  const keyFor = (app: string, topicName: string, object: string) =>
    `${app} ${topicName} ${object}`

  const open = async (app: string, topicName: string, object: string) => {
    setOpenKey(keyFor(app, topicName, object))
    setCategories(null)
    setTopic(null)
    try {
      const [loadedCategories, row] = await Promise.all([
        notificationsApi.listCategories(),
        notificationsApi.lookupTopic(app, topicName, object),
      ])
      setCategories(loadedCategories)
      setTopic(row)
    } catch (error) {
      // Reported rather than swallowed: this path used to fail invisibly.
      setCategories([])
      toast.error(getErrorMessage(error, t`Failed to load notification categories`))
    }
  }

  const close = () => {
    setOpenKey(null)
    setCategories(null)
    setTopic(null)
  }

  const changeCategory = async (row: NotificationTopic, category: string) => {
    setSaving(true)
    try {
      await notificationsApi.setTopicCategory(row, category)
      setTopic({ ...row, category: parseInt(category, 10) })
      const topicLabel = row.label || row.topic
      const chosen = categories?.find((c) => String(c.id) === category)
      const categoryLabel = chosen ? (chosen.display ?? chosen.label) : null
      toast.success(
        categoryLabel
          ? t`${topicLabel} moved to the ${categoryLabel} category`
          : t`Category updated`
      )
      close()
    } catch (error) {
      toast.error(getErrorMessage(error, t`Failed to update category`))
    } finally {
      setSaving(false)
    }
  }

  return { keyFor, openKey, categories, topic, saving, open, close, changeCategory }
}
