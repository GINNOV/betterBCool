# Expandable Activity history

Issue #33 requests the five latest changes by default, with a chevron to expand the history.

The section initially shows the five newest confirmed changes. When more exist, tapping the header or the log displays all retained changes; tapping again restores the five-entry view. The chevron switches between down and up. VoiceOver receives localized Expanded/Collapsed state. Clear remains a separate action and resets expansion. Empty history and the existing 50-entry retention limit are preserved.

Two UI regressions passed on a compact iPhone 17e running iOS 26.5. The new regression creates seven changes in English and Italian, checks five newest rows, expands to seven, collapses to five, and clears while expanded. The existing clear-history regression also passed. Explicit accessibility containers preserve the header, Clear control, and individual log entries.

![Collapsed Italian activity history](it-collapsed.png)

![Expanded Italian activity history](it-expanded.png)
