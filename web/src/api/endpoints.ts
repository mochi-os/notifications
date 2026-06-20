// Copyright © 2026 Mochi OÜ
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
} as const

export default endpoints
