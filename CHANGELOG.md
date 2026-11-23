# Changelog

All notable changes to Postie are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Postie uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Added

- The selected account, with its Google profile picture, at the bottom of the
  sidebar. Click it to switch accounts or add another one.
- All Inboxes above Inbox when more than one account is connected, showing every
  account's inbox together.
- Press Esc or ⌘← to close the open conversation. In the search field, Esc still
  clears the search and ⌘← still moves to the start of the line.
- A conversation's labels, such as Inbox and the ones you created in Gmail, next
  to its subject.
- Select several conversations with Shift or Command to archive them, move them to
  the Trash, mark them as read or unread, or forward them together in one message.
  Like Mail, Mark as Read marks them all read while any of them is unread. In a label
  or a search, Archive archives the selected ones that are in the Inbox. Reply and
  Reply All are disabled while several are selected.
- A checkbox under the unread dot when the pointer is over a conversation, as in
  Gmail. Checking conversations doesn't open them. Shift-click a checkbox to check
  or uncheck every conversation from the last one you clicked. While any are
  checked or several are selected, a bar under the list shows how many, with
  Select All and buttons to archive, trash, mark read or unread, forward, or
  deselect them all.
- Undo and Redo (⌘Z and ⇧⌘Z) for archiving, moving to the Trash, starring and
  marking as read or unread, back through as many steps as you like, like Mail. What
  comes back is selected again. The Edit menu names the step to undo.
- Priority Inbox, an option in Settings > General. It groups the Inbox into Important
  and unread, Starred, and Everything else, including older mail further down the
  Inbox. Click a heading to collapse its section. A conversation you open stays in its
  section after you move on, much as in Gmail, so reading or unstarring mail doesn't
  rearrange the list under you. The sections catch up when you switch to another window
  or app, choose Get New Mail, or leave the Inbox.
- Your Gmail labels in the sidebar, nested as they are in Gmail, with how many
  conversations are unread. Click one to see its mail. Labels you set to show only
  when unread, or to hide, are under More. Archiving in a label takes the conversation
  out of the Inbox and leaves it in the label.
- Postie remembers how wide you make the sidebar and the conversation list. Double-click
  the divider next to a column to put it back to its default width.
- A filter button above the conversation list, to show only the folder's unread mail,
  including mail further back than the list has loaded. A conversation you read stays
  until you move on. Choosing another folder or account turns the filter off.
- Mark a conversation as important or not important from the Message menu (⇧⌘I), its
  context menu, or the button next to its star. This can be undone. Important
  conversations show a marker in the list.
- Notifications for new mail in the Inbox, with who it is from, the subject and how
  it starts. Click one to open the conversation. When more than three messages
  arrive at once, such as after your Mac wakes up, they share one notification.
  While Postie is the app in front, they go straight to Notification Center. Turn
  them off in Settings > General.
- Open Postie at login, an option in Settings > General.
- Starred in the sidebar, below Inbox, with every starred conversation. As in a label,
  archiving one takes it out of the Inbox and leaves it in Starred. The Go menu
  shortcuts for the folders after it each move up one number.
- A reading pane button next to the filter button, and View > Reading Pane, to choose
  where conversations open, as in Gmail: Vertical Split (to the right of the list, as
  before), Horizontal Split (below the list), or No Split, where a conversation takes
  the list's place until you click the back button or press Esc or ⌘←. Postie
  remembers your choice.

### Changed

- Archiving or deleting the open conversation now goes back to the list, as Gmail
  does by default, instead of opening the next conversation. To keep opening the
  next one, choose it under After archiving or deleting in Settings > General.
- Inbox and the other folders now show only the selected account instead of every
  account merged. Search and new messages follow the account on screen.
- Opening Postie or a folder no longer opens the first conversation and marks it
  as read. Nothing is selected until you choose a conversation.
- Postie keeps running when you close its window, like Mail, so it can still tell
  you about new mail and keep the Dock badge up to date. Click its Dock icon to open
  the window again, and quit with ⌘Q.
- New mail shows up within about 30 seconds instead of up to five minutes. Postie
  asks Gmail whether anything has changed every 30 seconds, which takes one small
  request, and only syncs when something has.
- View > Text Size > Actual Size has no shortcut, as ⌘0 opens All Inboxes.
- Flag and Unflag are now Star and Unstar, the name Gmail uses, in the Message menu,
  the conversation's context menu, and the Edit menu's Undo.
- Click More in the sidebar's labels to open or close it. Its chevron now has the
  color of the sidebar's icons instead of a faint gray that was hard to see in dark mode.

### Fixed

- Some emails, such as boarding passes, no longer end in a very long empty area with
  an extra scrollbar.
- Images in table-based emails, such as logos in a header, are no longer squashed
  into a thin strip or hidden.
- Labels in table-based emails, such as delivery notices, no longer collapse into
  a narrow column with one letter per line, whether you are reading the email or
  quoting it in a reply or forward.
- Emails built with a table directly inside another table, such as LATAM boarding
  passes, keep their footer in the email's column instead of stretching it across
  the whole window. They are laid out as Gmail shows them.
- In dark mode, text no longer disappears in emails with colors of their own, such
  as a white card with default text. They are shown on a light page, as designed.
  Emails with no colors of their own, or that support dark mode, stay dark.
- Thin rule and spacer images in emails keep the size the email gives them instead
  of growing into large squares.
- Images embedded in an email, such as many signatures and logos, are now shown
  instead of an empty box. They are downloaded when the message is opened and then
  also work offline.
- Email images on servers that use plain HTTP now load.
- Web and email addresses written out as text in an email are now clickable.
- Collapsed messages in a conversation preview as much text as fits on the line
  instead of stopping at the first line break or after 100 characters.
- Accented letters in some emails no longer appear garbled, as in "dÃ­as". Mail
  already saved on your Mac is fixed as well.

## [0.5.0] - 2026-11-11

### Added

- Separate message-list text size setting in Settings > General, from 13 pt up to
  26 pt. Sender names, subjects, previews, and metadata scale together,
  independently of message-body zoom.
- Previous and next conversation controls, including keyboard shortcuts, and
  easier access to earlier replies in a conversation.
- Mailbox loading, search, and pagination status, plus progress indicators for
  archive and trash actions.

### Changed

- Larger default text in the message list for more comfortable reading.
- Conversation subjects stay visible above scrolling messages.
- Simpler recipient headers with expandable addresses, clearer conversation
  counts, and more readable text widths without changing authored HTML layouts.

### Fixed

- New conversations retain their full row height instead of clipping subjects
  and previews.
- Mail is automatically marked as read only while its reader window is active.

## [0.4.0] - 2026-11-10

### Added

- Calendar invitation cards with event details and Accept, Maybe and Decline
  responses sent through the Gmail account that received the invitation.
- Optional read-only Google Calendar access to show your existing response status.
- Reading text size controls under View > Text Size: Bigger (⌘+), Smaller (⌘−)
  and Actual Size (⌘0). The preference is remembered for HTML and plain-text
  email bodies.

### Fixed

- Automatic update checks are now enabled by default, while respecting an
  explicit choice to disable them in Settings.

## [0.3.0] - 2026-10-14

### Changed

- The conversation list no longer has a footer; more mail loads as you scroll.
- When Gmail rate-limits Postie, all requests now pause together and retry on a
  longer schedule instead of each backing off on its own.

### Fixed

- Conversations that were deleted outright are no longer fetched again and again
  during sync, which only produced errors.

## [0.2.0] - 2026-10-09

### Added

- A real Outbox: sent messages are saved on this Mac and delivered in the
  background, retried when the connection or Gmail is unavailable, and kept
  across quitting. Messages that cannot be sent stay in the Outbox, where they
  can be sent again, edited or deleted.
- Automatic updates: Postie checks for new releases in the background and
  installs them on request. Use Postie > Check for Updates… to check right now,
  or turn the automatic check off in Settings.

### Changed

- Message bodies are fetched in the background ahead of time, so conversations
  open faster, and a spinner shows while a body is still loading.

### Upgrading

- Version 0.1.0 cannot update itself. Download 0.2.0 from the
  [latest release](https://github.com/igorkulman/Postie/releases/latest) once;
  later versions will be offered inside Postie.

## [0.1.0] - 2026-10-07

First public release.

### Added

- Native SwiftUI Gmail client for macOS 26, with Google sign-in and the Gmail API
- Multiple Gmail accounts merged into one set of folders, with replies, forwards
  and archive/trash actions going through the account a conversation belongs to
- Inbox, Drafts, Sent, Archive, Junk and Trash
- Conversation view with HTML email rendering, scrolling long messages with the
  conversation and collapsing quoted history
- Rich-text compose, reply, reply all and forward with attachments and your
  Gmail signature
- Drafts saved in Gmail and editable from the Drafts folder
- Address suggestions from your Google contacts
- Search as you type across all accounts, in the current folder or All Mail
- Reading, opening, saving, sharing and copying attachments
- Archive, trash, star and read/unread actions
- Local SQLite cache and incremental synchronization
- Dock badge for unread Inbox mail
- Native light and dark mode

### Known limitations

- Postie is not verified by Google, so the sign-in screen shows "Google hasn't
  verified this app" (choose **Advanced > Go to Postie (unsafe)**) and the app is
  limited to 100 users
- No Gmail labels, CID (embedded) images or offline send queue yet

[0.1.0]: https://github.com/igorkulman/Postie/releases/tag/v0.1.0
[0.2.0]: https://github.com/igorkulman/Postie/releases/tag/v0.2.0
[0.3.0]: https://github.com/igorkulman/Postie/releases/tag/v0.3.0
[0.4.0]: https://github.com/igorkulman/Postie/releases/tag/v0.4.0
[0.5.0]: https://github.com/igorkulman/Postie/releases/tag/v0.5.0
