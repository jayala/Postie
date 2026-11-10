# Postie

A small native Gmail client for macOS, built with SwiftUI.

Postie is for people who want a simple Mac email client without Electron,
subscriptions, AI features, or workspace bloat.

![Postie](docs/postie.png)

## Features

- Native SwiftUI macOS app
- Gmail integration using Google sign-in and the Gmail API
- Multiple Gmail accounts: switch between them from your profile picture at the
  bottom of the sidebar, or read all of them together in All Inboxes. Replies,
  forwards and archive/trash actions always go through the account the conversation
  belongs to. New messages come from the account on screen, and in All Inboxes from
  the default account chosen in Settings
- Inbox, Drafts, Sent, Archive, Junk, and Trash
- Priority Inbox, optional in Settings: groups the Inbox into Important and unread,
  Starred, and Everything else, each of which can be collapsed. Older important and
  starred mail shows up there without scrolling to it. This is Postie's own setting,
  as Gmail doesn't let apps read yours
- Your Gmail labels in the sidebar, nested as in Gmail with their unread counts, for
  the selected account, including in All Inboxes. Labels Gmail is set not to list are
  under More
- Conversation view with HTML email rendering, and the conversation's Gmail labels
  next to its subject
- Compose, reply, reply all, and forward in a rich-text editor (bold, italic,
  underline, lists, links), with attachments and your Gmail signature
- Drafts are saved in Gmail, so they show up in every Gmail client: closing a
  message you have written asks whether to keep it, and drafts can be edited
  later from the Drafts folder
- Archive, trash, star, mark as important, and read/unread actions
- Select several conversations with Shift or Command to archive, trash, forward, or
  mark them as read or unread together. They are forwarded in one message
- A filter button above the conversation list shows only the folder's unread mail,
  including mail further back than the list has loaded. A conversation you read stays
  until you move on. Choosing another folder or account turns the filter off
- Undo and Redo (⌘Z and ⇧⌘Z) for archive, trash, flag, important, and read/unread, several
  steps back, until Postie quits. Deleting a draft or a queued message can't be undone
- Search as you type, powered by Gmail, in the account on screen or across all
  accounts from All Inboxes: search the current folder or All Mail, with Gmail operators such as `from:` and `has:attachment`.
  Results are not stored in the local cache
- Reading attachments: shown in the message header and as a chip in the list;
  double-click to open, or use the context menu to save, share, or copy
- Calendar invitations: event details and meeting links above the email body,
  with Accept, Maybe, and Decline replies sent through the receiving Gmail account.
  Supports inline calendar parts and `.ics` attachments, all-day events, and
  invitation updates/cancellations within a conversation. Optional **Connect Google
  Calendar…** access reads your response from the receiving account's primary
  calendar, including replies made in Gmail, Mimestream, or other calendar apps.
  It refreshes when opening an invitation or choosing **Refresh response**.
  Calendar access is read-only and not required for mail or email RSVPs; Postie
  does not display an agenda, modify calendars, or add events to a local calendar.
  Without Calendar access, Postie shows status only from the invitation and replies
  sent during the current app session. “Reply sent” confirms Gmail accepted the
  reply, not that the organizer’s calendar processed it
- Postie remembers how wide you make the sidebar and the conversation list.
  Double-click a divider to put that column back to its default width
- Local SQLite cache for previously loaded mail
- Incremental Gmail synchronization while the app is running. Postie asks Gmail
  whether anything has changed every 30 seconds and syncs when it has
- Notifications for new mail in the Inbox. Click one to open the conversation.
  More than three messages at once share one notification
- Postie keeps running after you close its window, like Mail, so notifications and
  the Dock badge keep working. It can open at login, in Settings > General
- Native light and dark mode
- Dock badge for unread Inbox mail

## Status

Postie is an early project that I built primarily as the Gmail client I wanted
to use myself.

It supports Gmail accounts only and is not intended to replace
every feature of Gmail or become a generic IMAP client.

Planned:

- Search suggestions (people and subjects)
- Changing Gmail labels
- Full offline mailbox downloads

Not planned:

- Generic IMAP / Exchange support
- Push notifications while Postie isn't running

## Privacy and permissions

Postie talks to Gmail directly from your Mac. There is no Postie server.

It asks for these Google permissions:

- `gmail.modify` to read mail, to archive, trash, star, and mark mail as important,
  read or unread, and to save and delete your drafts
- `gmail.send` to send mail
- `gmail.settings.basic` to read your signature, so new messages can include it.
  Postie never changes your Gmail settings
- `contacts.readonly` and `contacts.other.readonly` to read your Google contacts
  and the people you have written to, so the composer can suggest addresses.
  Postie never changes your contacts

Only if you choose **Connect Google Calendar…** on an invitation, it additionally
requests `calendar.events.readonly` to look up that invitation in your primary
Google Calendar and show your response. This is optional, is never used to modify
calendar events, and can be declined without affecting mail

Postie never permanently deletes mail. Trash is Gmail's normal, recoverable
Trash. Sign-in credentials stay in your Mac's Keychain,
and loaded mail and your contacts are cached in a local SQLite database on your Mac.

The Gmail ones are restricted scopes and Postie has not been verified
by Google, so the sign-in screen shows "Google hasn't verified this app". Choose
**Advanced > Go to Postie (unsafe)**, then tick all the permissions on the
next screen. Postie needs all of them to work. Unverified apps are limited to 100
users. If you fork Postie, create your own OAuth client in Google Cloud and put
it in `Configuration/Google.local.xcconfig` (see the `.example` file).

More details are in the [privacy policy](https://postie.kulman.sk/privacy).

## Download

Download the `.dmg` from the
[latest release](https://github.com/igorkulman/Postie/releases/latest), open it
and drag Postie to your Applications folder. The app is signed with a Developer ID
and notarized by Apple, and updates itself from then on. See [CHANGELOG.md](CHANGELOG.md) for what changed.

## Requirements

- macOS 26
- Xcode 27 (only to build it yourself)

## Running Postie from source

Open `Postie.xcodeproj`, choose the **Postie** scheme and **My Mac**, and run.
For optional Calendar response lookup, also enable the **Google Calendar API** in
the Google Cloud project that owns the OAuth client and configure the
`calendar.events.readonly` scope on its consent screen. Existing mail credentials
continue working; grant Calendar access from an invitation when you want to use it.

## Selection regression without a mailbox

In a Debug build, launch with `-PostieSelectionRegression` to run the real Gmail list/detail UI
against deterministic mail and an in-memory SQLite cache. It uses no real
credentials, network requests, or saved mailbox database.

1. No conversation is open at launch, and the detail column shows **No
   Conversation Selected**. Open **Thread to open**.
2. Choose **Regression > Insert Newer Mail**. The highlight and detail must stay
   on the same conversation, even though its row moved.
3. Archive it with **⌃⌘A**. **Next older thread** must become selected and open.
   Use the arrow keys immediately to check that keyboard focus is in the list.
4. Archive the remaining threads until the inbox is empty. Both selection and
   detail must clear, Archive/Trash must be disabled, and the empty list must
   retain keyboard focus. Inserting mail again must not automatically open it.
5. Press **⌘Z** repeatedly. Each archived thread must come back one at a time,
   newest action first, selected and in its place, and **⇧⌘Z** must archive them
   again. The Edit menu must name the step each time.

The Regression menu also simulates an external archive of **Thread to open**
and a rejected next archive/trash. External disappearance clears selection
without opening unrelated mail; rejection preserves the selected thread.

The policy is identity-based: a folder opens with nothing selected, Esc clears the
selection, and an explicit removal chooses the next surviving older neighbor from the visible order at action time,
then the nearest surviving newer neighbor, then no selection. Reordering never
changes a surviving selection. Removing an unselected thread or completing an
operation after the user changes selection does not choose a new thread.

Several selected threads stay closed and unread. Removing them chooses the next
neighbor past the oldest of them once they have all gone; threads Gmail refused
stay selected instead.

Add `-PostieLabels` to try the same mail with nested labels in the sidebar.

Add `-PostiePriorityInbox` to try the same mail in a Priority Inbox, with an
important unread thread and a starred one. Open **Important unread thread**: once
it is marked read it must stay in its section until another thread is selected.

## Tests

Run the **Postie** scheme's tests (⌘U). They use fixtures and need neither a
Google account nor network access.
