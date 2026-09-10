// Copyright © 2026 Mochisoft OÜ
// SPDX-License-Identifier: AGPL-3.0-only
// This file is part of Mochi, licensed under the GNU AGPL v3 with the
// Mochi Application Interface Exception - see license.txt and license-exception.md.
import { i18n } from '@lingui/core'
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'

// Activate a locale globally so the Lingui macro resolves. With none active
// the macro yields empty strings and a component renders as an empty tree,
// which reads in a failure as "the component did not mount".
i18n.loadAndActivate({ locale: 'en', messages: {} })

afterEach(() => {
  cleanup()
})

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})

// jsdom omits ResizeObserver and IntersectionObserver, which
// @formkit/auto-animate constructs on import. A class, not an arrow mock:
// arrows are not constructible.
class ObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
  takeRecords() {
    return []
  }
}
global.ResizeObserver = ObserverStub as unknown as typeof ResizeObserver
global.IntersectionObserver =
  ObserverStub as unknown as typeof IntersectionObserver

// Radix scrolls the active item into view, and @formkit/auto-animate calls
// el.animate() from a MutationObserver - outside any test's stack, so a missing
// Web Animations API fails the run without failing a test.
Element.prototype.scrollIntoView = vi.fn()
Element.prototype.animate = vi.fn().mockImplementation(() => ({
  cancel: vi.fn(),
  finish: vi.fn(),
  pause: vi.fn(),
  play: vi.fn(),
  reverse: vi.fn(),
  addEventListener: vi.fn(),
  removeEventListener: vi.fn(),
  finished: Promise.resolve(),
  onfinish: null,
})) as unknown as Element['animate']
