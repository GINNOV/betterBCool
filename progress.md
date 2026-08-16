Original prompt: add a log to show unit activities over time - also a button to clear the log

- In progress: add a session activity timeline to the SwiftUI dashboard.
- Decision: record confirmed unit control changes with timestamps; clearing the log only clears local history.
- Implemented: activity model, confirmed-change recording, 50-entry cap, dashboard timeline, empty state, and Clear button.
- Verification: `swift test` passes all 21 existing tests.
- UI verification: the new end-to-end XCUITest passes on iPhone 17 / iOS 26.5.
- Visual verification: inspected the populated dashboard card; the label, timestamp, icon, and Clear action are legible and aligned.
- Complete. No known loose ends.
