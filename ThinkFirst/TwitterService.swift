import Foundation
import Combine
import AuthenticationServices
import SwiftUI
import CryptoKit

class TwitterService: NSObject, ObservableObject {
    static let shared = TwitterService()

    @AppStorage("twitterClientID") var clientID: String = ""
    @AppStorage("twitterClientSecret") var clientSecret: String = ""
    @AppStorage("twitterAccessToken") private var accessToken: String = ""
    @AppStorage("twitterRefreshToken") private var refreshToken: String = ""
    @AppStorage("twitterTokenExpiry") private var tokenExpiry: Double = 0
    @AppStorage("twitterUserID") private var userID: String = ""
    @AppStorage("twitterLastSync") var lastSyncDate: Double = 0

    @Published var isAuthenticated: Bool = false
    @Published var bookmarks: [TwitterBookmark] = []
    @Published var isSyncing: Bool = false

    // PKCE
    private var codeVerifier: String?

    private override init() {
        super.init()
        checkAuthenticationStatus()
        loadBookmarks()
    }

    func checkAuthenticationStatus() {
        isAuthenticated = !accessToken.isEmpty
    }

    private var isTokenExpired: Bool {
        return Date().timeIntervalSince1970 >= tokenExpiry
    }

    // MARK: - OAuth Flow

    func authorize() {
        guard !clientID.isEmpty, !clientSecret.isEmpty else { return }

        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: "https://twitter.com/i/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "thinkfirst://auth"),
            URLQueryItem(name: "scope", value: "tweet.read users.read bookmark.read offline.access"),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components.url else { return }

        NSWorkspace.shared.open(url)
    }

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            return
        }

        exchangeCodeForToken(code: code, verifier: verifier)
    }

    private func exchangeCodeForToken(code: String, verifier: String) {
        let url = URL(string: "https://api.twitter.com/2/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyComponents = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": "thinkfirst://auth",
            "code_verifier": verifier
        ]

        performTokenRequest(request: request, bodyComponents: bodyComponents)
    }

    private func refreshAccessToken() async -> Bool {
        guard !refreshToken.isEmpty else { return false }

        let url = URL(string: "https://api.twitter.com/2/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyComponents = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]

        return await withCheckedContinuation { continuation in
            let credentials = "\(clientID):\(clientSecret)".data(using: .utf8)?.base64EncodedString() ?? ""
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

            request.httpBody = bodyComponents
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
                .data(using: .utf8)

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self, let data = data, error == nil else {
                    continuation.resume(returning: false)
                    return
                }

                do {
                    let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.accessToken = tokenResponse.access_token
                        if let newRefresh = tokenResponse.refresh_token {
                             self.refreshToken = newRefresh
                        }
                        self.tokenExpiry = Date().timeIntervalSince1970 + Double(tokenResponse.expires_in)
                        self.checkAuthenticationStatus()
                        continuation.resume(returning: true)
                    }
                } catch {
                    print("Token refresh failed: \(error)")
                    continuation.resume(returning: false)
                }
            }.resume()
        }
    }

    private func performTokenRequest(request: URLRequest, bodyComponents: [String: String]) {
        var mutableRequest = request
        let credentials = "\(clientID):\(clientSecret)".data(using: .utf8)?.base64EncodedString() ?? ""
        mutableRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        mutableRequest.httpBody = bodyComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: mutableRequest) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }

            do {
                let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.accessToken = tokenResponse.access_token
                    self?.refreshToken = tokenResponse.refresh_token ?? ""
                    self?.tokenExpiry = Date().timeIntervalSince1970 + Double(tokenResponse.expires_in)
                    self?.checkAuthenticationStatus()

                    // Fetch bookmarks immediately after auth
                    Task {
                        await self?.fetchMeAndBookmarks()
                    }
                }
            } catch {
                print("Token exchange failed: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    print("Response: \(str)")
                }
            }
        }.resume()
    }

    // MARK: - Bookmarks Logic

    func refreshData() async {
        DispatchQueue.main.async { self.isSyncing = true }
        defer { DispatchQueue.main.async { self.isSyncing = false } }

        if isTokenExpired {
            let refreshed = await refreshAccessToken()
            guard refreshed else { return }
        }

        await fetchMeAndBookmarks()
    }

    func fetchMeAndBookmarks() async {
        guard isAuthenticated else { return }

        // 1. Get Me (User ID) if needed
        if userID.isEmpty {
            await fetchMe()
        }

        guard !userID.isEmpty else { return }

        // 2. Fetch Bookmarks
        await refreshBookmarks()
    }

    private func fetchMe() async {
        let url = URL(string: "https://api.twitter.com/2/users/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(UserMeResponse.self, from: data)
            DispatchQueue.main.async {
                self.userID = response.data.id
            }
        } catch {
            print("Failed to fetch user: \(error)")
        }
    }

    func refreshBookmarks() async {
        guard !userID.isEmpty, !accessToken.isEmpty else { return }

        var components = URLComponents(string: "https://api.twitter.com/2/users/\(userID)/bookmarks")!
        components.queryItems = [
            URLQueryItem(name: "max_results", value: "100"),
            URLQueryItem(name: "expansions", value: "author_id,attachments.media_keys"),
            URLQueryItem(name: "user.fields", value: "profile_image_url,name,username"),
            URLQueryItem(name: "media.fields", value: "url,preview_image_url")
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Parse logic
            let response = try JSONDecoder().decode(BookmarksResponse.self, from: data)

            // Map data + includes to TwitterBookmark
            let mappedBookmarks: [TwitterBookmark] = response.data.compactMap { tweet in
                let author = response.includes?.users?.first(where: { $0.id == tweet.author_id })

                var imageUrl: String? = nil
                if let mediaKeys = tweet.attachments?.media_keys, let includesMedia = response.includes?.media {
                     if let firstMedia = includesMedia.first(where: { mediaKeys.contains($0.media_key) }) {
                        imageUrl = firstMedia.url ?? firstMedia.preview_image_url
                    }
                }

                return TwitterBookmark(
                    id: tweet.id,
                    text: tweet.text,
                    authorName: author?.name ?? "Unknown",
                    authorUsername: author?.username ?? "unknown",
                    profileImageUrl: author?.profile_image_url,
                    imageUrl: imageUrl
                )
            }

            DispatchQueue.main.async {
                self.bookmarks = mappedBookmarks
                self.lastSyncDate = Date().timeIntervalSince1970
                self.saveBookmarks()
            }

        } catch {
            print("Failed to fetch bookmarks: \(error)")
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            let url = getDocumentsDirectory().appendingPathComponent("bookmarks.json")
            try? data.write(to: url)
        }
    }

    private func loadBookmarks() {
        let url = getDocumentsDirectory().appendingPathComponent("bookmarks.json")
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode([TwitterBookmark].self, from: data) {
                self.bookmarks = decoded
            }
        }
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .ascii) else { return "" }
        let hashed = SHA256.hash(data: data)
        let hashData = Data(hashed)
        return hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

struct OAuthTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

struct TwitterBookmark: Identifiable, Codable {
    let id: String
    let text: String
    let authorName: String
    let authorUsername: String
    let profileImageUrl: String?
    let imageUrl: String?
}

// MARK: - API Response Models

struct UserMeResponse: Codable {
    struct UserData: Codable {
        let id: String
        let name: String
        let username: String
    }
    let data: UserData
}

struct BookmarksResponse: Codable {
    struct TweetData: Codable {
        let id: String
        let text: String
        let author_id: String?
        let attachments: Attachments?
    }
    struct Attachments: Codable {
        let media_keys: [String]?
    }
    struct Includes: Codable {
        let users: [User]?
        let media: [Media]?
    }
    struct User: Codable {
        let id: String
        let name: String
        let username: String
        let profile_image_url: String?
    }
    struct Media: Codable {
        let media_key: String
        let type: String
        let url: String?
        let preview_image_url: String?
    }

    let data: [TweetData]
    let includes: Includes?
}
