import Foundation
import Testing
@testable import Postie

@Suite("New mail notifications")
@MainActor
struct NewMailNotificationTests {
    private func mail(_ id: String, from name: String) -> NewMail {
        NewMail(threadID: "thread-" + id, messageID: id, senderName: name, senderEmail: "\(id)@example.com",
                subject: "Subject \(id)", snippet: "Snippet \(id)", date: Date(timeIntervalSince1970: 0))
    }

    @Test("Each message gets a notification of its own: who it is from, the subject and how it starts")
    func oneEach() throws {
        let notifications = MailNotifier.notifications(for: [mail("m1", from: "Sophie Chen"), mail("m2", from: "")], accountID: "acct")
        #expect(notifications.map(\.identifier) == ["acct/m1", "acct/m2"])
        let first = try #require(notifications.first?.content)
        #expect(first.title == "Sophie Chen")
        #expect(first.subtitle == "Subject m1")
        #expect(first.body == "Snippet m1")
        #expect(first.userInfo["account"] as? String == "acct")
        #expect(first.userInfo["thread"] as? String == "thread-m1")
        // Without a name, the address says who it is from.
        #expect(notifications.last?.content.title == "m2@example.com")
    }

    @Test("Past three messages at once, one notification counts them and names the latest senders")
    func summary() throws {
        let three = (1...3).map { mail("m\($0)", from: "Sender \($0)") }
        #expect(MailNotifier.notifications(for: three, accountID: "acct").count == 3)
        let arrived = [mail("m1", from: "Ann"), mail("m2", from: "Ben"), mail("m3", from: "Ann"), mail("m4", from: "Cy"), mail("m5", from: "Dee")]
        let notifications = MailNotifier.notifications(for: arrived, accountID: "acct")
        let only = try #require(notifications.first)
        #expect(notifications.count == 1)
        #expect(only.content.title == "5 new messages")
        #expect(only.content.body == "From " + ListFormatter.localizedString(byJoining: ["Dee", "Cy", "Ann", "others"]))
        // It opens the Inbox, not one of the conversations.
        #expect(only.content.userInfo["account"] as? String == "acct")
        #expect(only.content.userInfo["thread"] == nil)
    }

    @Test("Only unread mail that arrived in the Inbox, and wasn't sent from the account, is new, oldest first")
    func arrivals() {
        func message(_ id: String, _ labels: Set<String>, at seconds: TimeInterval) -> GmailMessage {
            GmailMessage(id: id, senderName: "Sam", senderEmail: "sam@example.com", recipient: "", cc: "",
                         date: Date(timeIntervalSince1970: seconds), snippet: "", body: "", labelIDs: labels)
        }
        let thread = GmailConversation(id: "t", subject: "Plans", messages: [
            message("earlier", ["INBOX", "UNREAD"], at: 1),
            message("new", ["INBOX", "UNREAD"], at: 20),
            message("read", ["INBOX"], at: 21),
            message("sent", ["INBOX", "UNREAD", "SENT"], at: 22),
            message("draft", ["DRAFT"], at: 23),
            message("trash", ["UNREAD", "TRASH"], at: 24),
            message("newer", ["INBOX", "UNREAD", "IMPORTANT"], at: 30)
        ])
        let added: Set<String> = ["new", "read", "sent", "draft", "trash", "newer"]
        let arrived = NewMail.arrivals(added, in: [thread])
        #expect(arrived.map(\.messageID) == ["new", "newer"])
        #expect(arrived.allSatisfy { $0.threadID == "t" && $0.subject == "Plans" })
    }
}
