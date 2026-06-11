//
//  FreesoundClient.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public protocol FreesoundHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FreesoundHTTPClient {}

public enum FreesoundAuthentication: Sendable, Equatable {
    case none
    case apiKey(String)
    case oauthToken(String)
}

public final class FreesoundClient {
    public let baseURL: URL
    public var authentication: FreesoundAuthentication

    private let session: FreesoundHTTPClient
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = URL(string: "https://freesound.org/apiv2")!,
        authentication: FreesoundAuthentication = .none,
        session: FreesoundHTTPClient = URLSession.shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.session = session
        self.decoder = decoder
    }

    // MARK: - Searching

    public func textSearch(query: String, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        var allParameters = parameters
        allParameters["query"] = query
        return try await send(path: "/search/text/", query: allParameters)
    }

    public func contentSearch(parameters: [String: String?] = [:]) async throws -> PagedResponse<
        Sound
    > {
        try await send(path: "/search/content/", query: parameters)
    }

    public func combinedSearch(parameters: [String: String?] = [:]) async throws -> PagedResponse<
        Sound
    > {
        try await send(path: "/search/combined/", query: parameters)
    }

    // MARK: - Sounds

    public func sound(id: Int, fields: String? = nil) async throws -> Sound {
        try await send(path: "/sounds/\(id)/", query: ["fields": fields])
    }

    public func soundAnalysis(id: Int, descriptors: String? = nil, normalized: Bool? = nil)
        async throws -> SoundAnalysis
    {
        var query: [String: String?] = [:]
        query["descriptors"] = descriptors
        if let normalized {
            query["normalized"] = normalized ? "1" : "0"
        }
        return try await send(path: "/sounds/\(id)/analysis/", query: query)
    }

    public func similarSounds(id: Int, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        try await send(path: "/sounds/\(id)/similar/", query: parameters)
    }

    public func soundComments(id: Int, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Comment>
    {
        try await send(path: "/sounds/\(id)/comments/", query: parameters)
    }

    public func downloadOriginalSound(id: Int) async throws -> Data {
        try await sendData(path: "/sounds/\(id)/download/", requiresOAuth: true)
    }

    public func uploadSound(
        fileURL: URL,
        request: SoundUploadRequest? = nil,
        fileFieldName: String = "audiofile"
    ) async throws -> UploadSoundResponse {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = multipartBody(
            fields: request?.asFormFields ?? [:],
            fileFieldName: fileFieldName,
            fileName: fileURL.lastPathComponent,
            fileData: fileData,
            mimeType: mimeType(forFileExtension: fileURL.pathExtension),
            boundary: boundary
        )
        return try await send(
            path: "/sounds/upload/",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            requiresOAuth: true
        )
    }

    public func describeSound(request: SoundDescribeRequest) async throws -> APIStatusResponse {
        let body = formEncodedBody(request.asFormFields)
        return try await send(
            path: "/sounds/describe/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            requiresOAuth: true
        )
    }

    public func pendingUploads() async throws -> PendingUploads {
        try await send(path: "/sounds/pending_uploads/", requiresOAuth: true)
    }

    public func bookmarkSound(soundID: Int, name: String? = nil, category: String? = nil)
        async throws -> APIStatusResponse
    {
        var fields: [String: String] = [:]
        if let name {
            fields["name"] = name
        }
        if let category {
            fields["category"] = category
        }
        let body = formEncodedBody(fields)
        return try await send(
            path: "/sounds/\(soundID)/bookmark/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            requiresOAuth: true
        )
    }

    public func rateSound(soundID: Int, rating: Int) async throws -> APIStatusResponse {
        guard (0...5).contains(rating) else {
            throw FreesoundError.invalidInput("rating must be in 0...5")
        }
        let body = formEncodedBody(["rating": String(rating)])
        return try await send(
            path: "/sounds/\(soundID)/rate/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            requiresOAuth: true
        )
    }

    public func commentSound(soundID: Int, comment: String) async throws -> APIStatusResponse {
        let body = formEncodedBody(["comment": comment])
        return try await send(
            path: "/sounds/\(soundID)/comment/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            requiresOAuth: true
        )
    }

    // MARK: - Users

    public func user(username: String) async throws -> User {
        try await send(path: "/users/\(encodedPathComponent(username))/")
    }

    public func userSounds(username: String, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        try await send(path: "/users/\(encodedPathComponent(username))/sounds/", query: parameters)
    }

    public func userPacks(username: String, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Pack>
    {
        try await send(path: "/users/\(encodedPathComponent(username))/packs/", query: parameters)
    }

    // MARK: - Packs

    public func pack(id: Int) async throws -> Pack {
        try await send(path: "/packs/\(id)/")
    }

    public func packSounds(id: Int, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        try await send(path: "/packs/\(id)/sounds/", query: parameters)
    }

    public func downloadPack(id: Int) async throws -> Data {
        try await sendData(path: "/packs/\(id)/download/", requiresOAuth: true)
    }

    // MARK: - Me / bookmarks

    public func me() async throws -> Me {
        try await send(path: "/me/", requiresOAuth: true)
    }

    public func myBookmarkCategories(parameters: [String: String?] = [:]) async throws
        -> PagedResponse<BookmarkCategory>
    {
        try await send(path: "/me/bookmark_categories/", query: parameters, requiresOAuth: true)
    }

    public func myBookmarkCategorySounds(categoryID: Int, parameters: [String: String?] = [:])
        async throws -> PagedResponse<Sound>
    {
        try await send(
            path: "/me/bookmark_categories/\(categoryID)/sounds/", query: parameters,
            requiresOAuth: true)
    }

    // MARK: - OAuth2 helpers

    public func oauthAuthorizationURL(
        clientID: String,
        responseState: String? = nil,
        redirectURI: String? = nil,
        forceLogin: Bool = false
    ) throws -> URL {
        var query: [String: String?] = [
            "client_id": clientID,
            "response_type": "code",
        ]
        query["state"] = responseState
        query["redirect_uri"] = redirectURI

        let path = forceLogin ? "/oauth2/logout_and_authorize/" : "/oauth2/authorize/"
        return try buildURL(path: path, query: query)
    }

    public func exchangeAuthorizationCode(
        clientID: String,
        clientSecret: String,
        code: String
    ) async throws -> OAuthTokenResponse {
        let formData = formEncodedBody([
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code,
        ])
        return try await send(
            path: "/oauth2/access_token/",
            method: "POST",
            body: formData,
            contentType: "application/x-www-form-urlencoded",
            authenticationOverride: .some(.none)
        )
    }

    public func refreshAccessToken(
        clientID: String,
        clientSecret: String,
        refreshToken: String
    ) async throws -> OAuthTokenResponse {
        let formData = formEncodedBody([
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        return try await send(
            path: "/oauth2/access_token/",
            method: "POST",
            body: formData,
            contentType: "application/x-www-form-urlencoded",
            authenticationOverride: .some(.none)
        )
    }

    // MARK: - Internal request plumbing

    private func send<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        requiresOAuth: Bool = false,
        authenticationOverride: FreesoundAuthentication? = nil
    ) async throws -> T {
        let auth = authenticationOverride ?? authentication
        var request = try URLRequest(url: buildURL(path: path, query: query))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        try applyAuth(auth: auth, requiresOAuth: requiresOAuth, to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FreesoundError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapAPIError(statusCode: httpResponse.statusCode, data: data)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw FreesoundError.decodingError(String(describing: error))
            }
        } catch let error as FreesoundError {
            throw error
        } catch {
            throw FreesoundError.transportError(String(describing: error))
        }
    }

    private func sendData(
        path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        requiresOAuth: Bool = false
    ) async throws -> Data {
        var request = try URLRequest(url: buildURL(path: path, query: query))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        try applyAuth(auth: authentication, requiresOAuth: requiresOAuth, to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FreesoundError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapAPIError(statusCode: httpResponse.statusCode, data: data)
            }
            return data
        } catch let error as FreesoundError {
            throw error
        } catch {
            throw FreesoundError.transportError(String(describing: error))
        }
    }

    private func applyAuth(
        auth: FreesoundAuthentication, requiresOAuth: Bool, to request: inout URLRequest
    ) throws {
        switch auth {
        case .none:
            if requiresOAuth {
                throw FreesoundError.oauthRequired
            }
        case .apiKey(let token):
            if requiresOAuth {
                throw FreesoundError.oauthRequired
            }
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        case .oauthToken(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func buildURL(path: String, query: [String: String?]) throws -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: base + path) else {
            throw FreesoundError.invalidBaseURL(baseURL.absoluteString)
        }
        let queryItems = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw FreesoundError.invalidBaseURL(baseURL.absoluteString)
        }
        return url
    }

    private func mapAPIError(statusCode: Int, data: Data) -> FreesoundError {
        struct ErrorPayload: Decodable {
            let detail: String?
        }

        let detail = (try? decoder.decode(ErrorPayload.self, from: data))?.detail ?? "Unknown error"
        return .apiError(statusCode: statusCode, detail: detail)
    }

    private func formEncodedBody(_ params: [String: String]) -> Data {
        let pairs = params.map { key, value in
            let encodedKey = encodedFormValue(key)
            let encodedValue = encodedFormValue(value)
            return "\(encodedKey)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private func encodedFormValue(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._* ")
        return
            value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }

    private func encodedPathComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func multipartBody(
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        fileData: Data,
        mimeType: String,
        boundary: String
    ) -> Data {
        var body = Data()

        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n"
                .data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func mimeType(forFileExtension ext: String) -> String {
        switch ext.lowercased() {
        case "wav":
            return "audio/wav"
        case "aif", "aiff":
            return "audio/aiff"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }
}
