import Foundation
import Security

/// Sends alerts to a phone through ntfy (https://ntfy.sh): install the ntfy app
/// and subscribe to the topic. Off by default; the only network calls Pulse makes.
enum PhoneNotifier {
    enum Kind { case finished, permission, test }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// A topic nobody can guess: anyone who knows it can read the alerts.
    static func randomTopic() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let alphabet = Array("abcdefghijkmnopqrstuvwxyz23456789")
        return "claude-pulse-" + String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func send(server: String, topic: String, title: String, message: String, kind: Kind,
                     completion: ((String?) -> Void)? = nil) {
        let trimmedServer = server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !topic.isEmpty, let url = URL(string: trimmedServer), url.scheme == "https" else {
            completion?("Server must be an https URL and the topic can't be empty.")
            return
        }
        // JSON publishing keeps titles UTF-8 safe (ntfy headers are ASCII only).
        let payload: [String: Any] = [
            "topic": topic,
            "title": title,
            "message": message.isEmpty ? title : message,
            "priority": kind == .permission ? 4 : 3,
            "tags": [kind == .permission ? "raised_hand" : "white_check_mark"],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        session.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let failure = error?.localizedDescription ?? ((200..<300).contains(status) ? nil : "Server answered \(status).")
            Notifier.log("phone (\(topic.prefix(16))…): \(title)\(failure.map { " | error: \($0)" } ?? "")")
            DispatchQueue.main.async { completion?(failure) }
        }.resume()
    }
}
