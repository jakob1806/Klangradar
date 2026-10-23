import UserNotifications

/// Lädt das Bild einer Push-Mitteilung ("image_url" im Payload, gesetzt vom
/// push-dispatcher) und hängt es als Vorschau an. Ohne Bild oder bei
/// Zeitüberschreitung kommt die Mitteilung unverändert an.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        bestAttempt = content

        guard let raw = request.content.userInfo["image_url"] as? String, let url = URL(string: raw) else {
            contentHandler(content)
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { location, response, _ in
            defer { contentHandler(content) }
            guard let location else { return }
            let ext = (response?.mimeType == "image/png") ? "png" : "jpg"
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            do {
                try FileManager.default.moveItem(at: location, to: target)
                let attachment = try UNNotificationAttachment(identifier: "image", url: target)
                content.attachments = [attachment]
            } catch {
                // Ohne Bild weiter.
            }
        }
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt { contentHandler(bestAttempt) }
    }
}
