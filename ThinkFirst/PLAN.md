Agent task: Fix auto-sizing + layout for StickyNote window (Prayer mode)

File: ThinkFirst/ThinkFirst/StickyNoteWindow.swift

Problem

We have a floating sticky note window with:
    1.    a native NSTextView editor (top section), and
    2.    an optional Prayer mode UI (bottom section).

Right now, when Prayer mode is enabled (or when text wraps/changes height), the text editor clips because the window does not reliably resize to fit the combined content. Prayer UI itself does not clip; only the editor does. There is no jitter/bounce, but the user can manually resize height, which we don’t want.

Goal (non-negotiable)

The window must always show all text and the Prayer section with no clipping and no scrolling (no vertical scrollers, no internal scroll behavior). The window height should be fully driven by content, and should update immediately and deterministically.

Required behavior

Two distinct vertical sections
    •    Layout is a clean vertical stack:
    •    Section A: Text editor (always visible)
    •    Section B: Prayer UI (visible only if Prayer mode enabled), displayed below the editor.
    •    Both sections must be visible at the same time when Prayer mode is enabled.

Auto-resize height (programmatic only)
    •    Users must not be able to manually resize height.
    •    The app can and should resize height programmatically based on content.
    •    There is no max height (window can grow indefinitely). The only “limits” should be practicality / screen, but do not clamp height in code.
    •    Resizing must be not animated.

Text must never scroll
    •    Do not allow scrolling in the text editor area.
    •    Do not allow vertical scroll view behavior.
    •    The window should grow/shrink so the entire text content is visible.

Resize triggers
    •    Typing / deleting: as the user types and the text height changes (e.g., new line or wrap), the window height must update immediately.
    •    Width changes: users can resize width manually (this already works well). When width decreases and wrapping creates more lines, the window height must recompute and update accordingly.
    •    Prayer mode toggle: enabling Prayer mode must immediately resize the window to fit textHeight + prayerHeight. Disabling must shrink back to fit just text.
    •    Not editing: even when not editing, the window must still fit the full text content (no clipping).

Prayer section sizing
    •    Prayer section is dynamic, but in practice it stays small (few elements) and should not become “very tall.”
    •    Prayer content updates (times/location formatting) do not require ongoing resizing, because the layout size won’t meaningfully change. (But toggling Prayer on/off does.)

Trailing empty lines rule (on end editing)
When the user ends editing (Done / Escape / click outside / app loses focus):
    •    Remove all trailing empty lines / newlines / end whitespace after the last non-empty line.
    •    Keep intentional blank lines inside the text (don’t collapse internal spacing).

Example:
    •    "Hello\n\n" → "Hello"
    •    "Hello\n\nWorld\n\n" → "Hello\n\nWorld"
    •    "Hello\n   \n" → "Hello"

Overlays and interactions
    •    Done button remains a pure overlay and must not consume layout space.
    •    Dragging should remain possible from anywhere in the window (entire surface), including prayer area.
    •    No jitter / no resize loops.

Implementation constraints / preference
    •    Prefer a mac-native, low-overhead approach. Avoid expensive polling and avoid feedback loops that cause redundant resizing.
    •    Keep the existing width resizing behavior and padding (left/right/top padding is good).
    •    Remove/disable user-driven vertical resizing while preserving programmatic resizing.

Acceptance criteria
    1.    Toggle Prayer mode ON with existing multi-line text: no text clipping, window grows to show full editor + prayer UI.
    2.    Toggle Prayer mode OFF: window shrinks to show full text only.
    3.    Type new lines / delete lines: window grows/shrinks immediately.
    4.    Resize width narrower so text wraps: window height updates so all lines are visible.
    5.    End editing with extra blank lines at the end: trailing blank lines are removed and not persisted.
    6.    User cannot drag-resize window height manually, but width resizing still works.
    7.    No scrolling is introduced anywhere; no animations.
    8.    Make it as simple as possible, remove code we don't need
