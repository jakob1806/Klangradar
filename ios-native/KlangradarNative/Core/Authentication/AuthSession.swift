import Foundation

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Int?
    let tokenType: String
    let user: AuthUser

    var expirationDate: Date {
        if let expiresAt {
            return Date(timeIntervalSince1970: TimeInterval(expiresAt))
        }
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

struct AuthUser: Codable, Identifiable, Sendable {
    let id: UUID
    let email: String?
    let isAnonymous: Bool?
}
