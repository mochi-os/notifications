// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.

const endpoints = {
  notifications: {
    list: '-/list',
    read: '-/read',
    readAll: '-/read/all',
    clearAll: '-/clear/all',
  },
  // This app owns the notifications service, so it reads categories and topics
  // from its own actions. The shared category button used to fetch the menu
  // app's equivalents with this app's token, which core refuses.
  categories: {
    list: '-/categories/list',
  },
  topics: {
    lookup: '-/topics/lookup',
    setCategory: '-/topics/set_category',
  },
} as const

export default endpoints
