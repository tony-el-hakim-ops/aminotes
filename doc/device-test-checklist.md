# Device test checklist (M9)

Run the example app on each real device:
`cd example && flutter run -d <device>` (or `flutter run --release`).
Tick each line per device; note anything odd with a screenshot.

| | Note 9 (Android 10) | iPhone | Android 7 phone (if available) |
|---|---|---|---|
| Device / OS version | | | |
| Android System WebView / Safari version | | | |

## Editing
- [ ] Tap the box: keyboard opens, toolbar sits right above it
- [ ] Type English, then Arabic in a new paragraph: each paragraph takes its own direction
- [ ] Bold / italic / underline / colors / highlight apply and show active
- [ ] Lists, checklist (tap a checkbox), indent / outdent
- [ ] Drag the toolbar sideways; the keyboard stays open
- [ ] Hide the keyboard (system back on Android / swipe down on iOS): toolbar goes away
- [ ] Undo / redo in full screen
- [ ] Long note: the caret stays visible while typing at the bottom

## Box and full screen
- [ ] The box grows as you type, up to its maximum, then scrolls
- [ ] Full screen: text, cursor and undo come along; back again keeps them
- [ ] Rotate the phone in both views

## Links
- [ ] Add link (full screen toolbar), edit it, remove it
- [ ] Tap a link in the note: the app's dialog shows the URL

## Voice notes
- [ ] First recording asks for the microphone; Deny shows the message
- [ ] Record 5 s, Done: the voice note lands at the cursor
- [ ] Record, press Home, come back: the recording was saved
- [ ] A phone call during recording (if you can): the recording was saved
- [ ] Tap a voice note: plays with the player bar; seek, pause, delete
- [ ] Play with the phone's silent switch on (iPhone): you still hear it

## Images
- [ ] Add from gallery, add from the camera
- [ ] Tap an image: View (pinch zoom), Delete, Undo
- [ ] Upload media (simulated): sources become https URLs

## Saving
- [ ] Type, then immediately press Home: "saved" count went up
- [ ] Type, then immediately leave the note list's editor: the list shows the edit
- [ ] Kill the app from recents while typing; reopen (host app's job to reload; note what was saved)

## Look
- [ ] Dark mode, Arabic layout, large system font size
- [ ] Notes list: previews look like the notes

## Speed
- [ ] Time from opening the screen to the box being ready (about): ___
- [ ] Typing in a long note (sample note x3) stays smooth
