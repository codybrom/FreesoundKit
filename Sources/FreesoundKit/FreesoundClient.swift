//
//  FreesoundClient.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/9/26.
//

import Dispatch
import Foundation
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Performs the underlying HTTP request for a ``FreesoundClient``.
///
/// `URLSession` conforms to this protocol by default. Provide a custom
/// conformance to stub network responses in tests or to route requests
/// through your own transport.
public protocol FreesoundHTTPClient: Sendable {
    /// Fetches the data for the given request.
    /// - Parameter request: The request to perform.
    /// - Returns: The response body and metadata.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FreesoundHTTPClient {}

#if canImport(FoundationNetworking)
    // Darwin Foundation declares URLSession Sendable but corelibs-foundation
    // does not, even though URLSession is documented as thread-safe.
    extension URLSession: @retroactive @unchecked Sendable {}

    // corelibs-foundation lacks Darwin's async data(for:), so bridge the
    // completion-handler API to satisfy FreesoundHTTPClient.
    extension URLSession {
        public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try await withCheckedThrowingContinuation { continuation in
                dataTask(with: request) { data, response, error in
                    if let data, let response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: error ?? URLError(.badServerResponse))
                    }
                }.resume()
            }
        }
    }
#endif

/// The credential a ``FreesoundClient`` sends with each request.
public enum FreesoundAuthentication: Sendable, Equatable {
    /// No credential is sent. Only unauthenticated endpoints will succeed.
    case none
    /// A Freesound API key, sent as an `Authorization: Token …` header.
    ///
    /// Sufficient for read-only endpoints, but not for write actions,
    /// downloads, or `/me`, which require OAuth2.
    case apiKey(String)
    /// An OAuth2 access token, sent as an `Authorization: Bearer …` header.
    ///
    /// Required for write actions, downloads, and user-scoped endpoints.
    case oauthToken(String)
}

/// A client for the [Freesound API v2](https://freesound.org/docs/api/).
///
/// Create a client with the credential appropriate to the endpoints you need,
/// then call the endpoint methods. Read-only search and lookup endpoints work
/// with an ``FreesoundAuthentication/apiKey(_:)``; write actions, downloads,
/// and user-scoped endpoints (`/me`) require an
/// ``FreesoundAuthentication/oauthToken(_:)``.
///
/// ```swift
/// let client = FreesoundClient(authentication: .apiKey("YOUR_API_KEY"))
/// let results = try await client.textSearch(query: "rain")
/// ```
///
/// Every endpoint method throws ``FreesoundError`` on failure.
///
/// The client is `Sendable`: a single instance can be shared across tasks and
/// actors, and ``authentication`` may be updated from any thread.
public final class FreesoundClient: Sendable {
    /// The API root that request paths are resolved against.
    public let baseURL: URL
    /// The credential sent with each request. Update this after refreshing an
    /// OAuth token without recreating the client. Thread-safe.
    public var authentication: FreesoundAuthentication {
        get { authenticationStorage.withLock { $0 } }
        set { authenticationStorage.withLock { $0 = newValue } }
    }

    private let authenticationStorage: Mutex<FreesoundAuthentication>
    private let session: FreesoundHTTPClient
    private let decoder: JSONDecoder

    /// Creates a client.
    /// - Parameters:
    ///   - baseURL: The API root. Defaults to `https://freesound.org/apiv2`.
    ///   - authentication: The credential to send. Defaults to ``FreesoundAuthentication/none``.
    ///   - session: The HTTP transport. Defaults to `URLSession.shared`; inject a
    ///     custom ``FreesoundHTTPClient`` to stub requests in tests.
    ///   - decoder: The JSON decoder used for response bodies. Do not mutate it
    ///     after passing it in; the client may use it from multiple threads.
    public init(
        baseURL: URL = URL(string: "https://freesound.org/apiv2")!,
        authentication: FreesoundAuthentication = .none,
        session: FreesoundHTTPClient = URLSession.shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.authenticationStorage = Mutex(authentication)
        self.session = session
        self.decoder = decoder
    }

    // MARK: - Searching

    /// Searches sounds by text query.
    /// - Parameters:
    ///   - query: The search terms.
    ///   - parameters: Optional query parameters (for example `filter`, `sort`,
    ///     `page`, `page_size`, `fields`). `nil` values are omitted.
    /// - Returns: A page of matching ``Sound`` results.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func textSearch(query: String, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        var allParameters = parameters
        allParameters["query"] = query
        return try await send(path: "/search/text/", query: allParameters)
    }

    /// Searches sounds by audio content (descriptor target/filter).
    /// - Parameter parameters: Query parameters such as `target` and
    ///   `descriptors_filter`. `nil` values are omitted.
    /// - Returns: A page of matching ``Sound`` results.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func contentSearch(parameters: [String: String?] = [:]) async throws -> PagedResponse<
        Sound
    > {
        try await send(path: "/search/content/", query: parameters)
    }

    /// Searches sounds using both text and audio-content criteria.
    ///
    /// Unlike the other search endpoints, combined search does not report a
    /// total count or page numbers; fetch further results with
    /// ``moreResults(of:)``.
    /// - Parameter parameters: Combined text and content query parameters.
    ///   `nil` values are omitted.
    /// - Returns: The matching ``Sound`` results and an optional `more` link.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func combinedSearch(parameters: [String: String?] = [:]) async throws
        -> CombinedSearchResponse
    {
        try await send(path: "/search/combined/", query: parameters)
    }

    /// Fetches the next batch of combined-search results.
    /// - Parameter response: A previous combined-search response.
    /// - Returns: The next batch, or `nil` if `response` has no `more` link.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func moreResults(of response: CombinedSearchResponse) async throws
        -> CombinedSearchResponse?
    {
        guard let more = response.more else { return nil }
        return try await send(url: resolveLink(more))
    }

    // MARK: - Pagination

    /// Fetches the page of results at a URL previously returned by the API.
    /// - Parameter url: A page URL, such as ``PagedResponse/next`` or
    ///   ``PagedResponse/previous``.
    /// - Returns: The requested page.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func page<Item: Decodable & Sendable>(at url: URL) async throws -> PagedResponse<Item> {
        try await send(url: url)
    }

    /// Fetches the page after the given one.
    /// - Parameter page: A previously fetched page.
    /// - Returns: The next page, or `nil` if `page` is the last one.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func nextPage<Item: Decodable & Sendable>(of page: PagedResponse<Item>) async throws
        -> PagedResponse<Item>?
    {
        guard let next = page.next else { return nil }
        return try await send(url: next)
    }

    /// Fetches the page before the given one.
    /// - Parameter page: A previously fetched page.
    /// - Returns: The previous page, or `nil` if `page` is the first one.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func previousPage<Item: Decodable & Sendable>(of page: PagedResponse<Item>) async throws
        -> PagedResponse<Item>?
    {
        guard let previous = page.previous else { return nil }
        return try await send(url: previous)
    }

    // MARK: - Sounds

    /// Fetches metadata for a single sound.
    /// - Parameters:
    ///   - id: The sound's identifier.
    ///   - fields: A comma-separated list of fields to return, or `nil` for the default set.
    /// - Returns: The requested ``Sound``.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func sound(id: Int, fields: String? = nil) async throws -> Sound {
        try await send(path: "/sounds/\(id)/", query: ["fields": fields])
    }

    /// Fetches the audio analysis (descriptors) for a sound.
    /// - Parameters:
    ///   - id: The sound's identifier.
    ///   - descriptors: A comma-separated list of descriptors to return, or `nil` for all.
    ///   - normalized: Whether to return normalized descriptor values.
    /// - Returns: The sound's ``SoundAnalysis``.
    /// - Throws: ``FreesoundError`` if the request fails.
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

    /// Fetches sounds acoustically similar to a given sound.
    /// - Parameters:
    ///   - id: The reference sound's identifier.
    ///   - parameters: Optional query parameters such as `fields`, `page`, `page_size`.
    /// - Returns: A page of similar ``Sound`` results.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func similarSounds(id: Int, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        try await send(path: "/sounds/\(id)/similar/", query: parameters)
    }

    /// Fetches the comments on a sound.
    /// - Parameters:
    ///   - id: The sound's identifier.
    ///   - parameters: Optional pagination parameters such as `page`, `page_size`.
    /// - Returns: A page of ``Comment`` values.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func soundComments(id: Int, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Comment>
    {
        try await send(path: "/sounds/\(id)/comments/", query: parameters)
    }

    /// Downloads the original audio file for a sound.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``; an API key is not sufficient.
    /// - Parameter id: The sound's identifier.
    /// - Returns: The raw audio file data.
    /// - Throws: ``FreesoundError/oauthRequired`` if the client is not OAuth-authenticated,
    ///   or another ``FreesoundError`` if the request fails.
    public func downloadOriginalSound(id: Int) async throws -> Data {
        try await sendData(path: "/sounds/\(id)/download/", requiresOAuth: true)
    }

    /// Downloads the preview (lossy-compressed) audio for a sound.
    ///
    /// Preview files are public, so this works with any ``authentication`` —
    /// unlike ``downloadOriginalSound(id:)``, which requires OAuth.
    /// - Parameters:
    ///   - sound: The sound to fetch a preview of. Its ``Sound/previews`` must
    ///     be populated (include `previews` in the requested `fields`).
    ///   - format: The preview encoding to fetch. Defaults to high-quality MP3.
    /// - Returns: The raw preview audio data.
    /// - Throws: ``FreesoundError/invalidInput(_:)`` if the sound has no URL for
    ///   the requested format, or another ``FreesoundError`` if the request fails.
    public func downloadPreview(for sound: Sound, format: SoundPreviewFormat = .hqMP3)
        async throws -> Data
    {
        guard let previews = sound.previews else {
            throw FreesoundError.invalidInput(
                "Sound \(sound.id) has no preview URLs; include \"previews\" in the requested fields."
            )
        }
        let previewURL: URL? =
            switch format {
            case .hqMP3: previews.previewHQMP3
            case .lqMP3: previews.previewLQMP3
            case .hqOGG: previews.previewHQOGG
            case .lqOGG: previews.previewLQOGG
            }
        guard let previewURL else {
            throw FreesoundError.invalidInput(
                "Sound \(sound.id) has no \(format) preview URL.")
        }
        return try await sendData(url: previewURL, applyAuthentication: false)
    }

    /// Uploads an audio file to the authenticated user's account.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``. If `request`
    /// includes the required description fields the sound is submitted for
    /// processing; otherwise it remains a pending upload to be described later
    /// with ``describeSound(request:)``.
    /// - Parameters:
    ///   - fileURL: The local audio file to upload.
    ///   - request: Optional description metadata to send alongside the file.
    ///   - fileFieldName: The multipart field name for the file. Defaults to `"audiofile"`.
    /// - Returns: The upload result, including the new sound or pending-upload identifier.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if reading the file or the request fails.
    public func uploadSound(
        fileURL: URL,
        request: SoundUploadRequest? = nil,
        fileFieldName: String = "audiofile"
    ) async throws -> UploadSoundResponse {
        let fileData = try await Self.readFile(at: fileURL)
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

    /// Adds description metadata to a previously uploaded (pending) sound.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Parameter request: The description fields to apply.
    /// - Returns: The API status response.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
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

    /// Edits the description metadata of an already-described sound.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)`` and that the sound
    /// belongs to the authenticated user. Only the fields set on `request` are
    /// sent; the rest keep their current values.
    /// - Parameters:
    ///   - soundID: The sound's identifier.
    ///   - request: The fields to change.
    /// - Returns: The API status response.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
    public func editSound(soundID: Int, request: SoundEditRequest) async throws
        -> APIStatusResponse
    {
        let body = formEncodedBody(request.asFormFields)
        return try await send(
            path: "/sounds/\(soundID)/edit/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            requiresOAuth: true
        )
    }

    /// Lists the authenticated user's sounds that are pending processing or description.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Returns: The pending and processing uploads.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
    public func pendingUploads() async throws -> PendingUploads {
        try await send(path: "/sounds/pending_uploads/", requiresOAuth: true)
    }

    /// Bookmarks a sound for the authenticated user.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Parameters:
    ///   - soundID: The sound's identifier.
    ///   - name: An optional name for the bookmark.
    ///   - category: An optional bookmark category to file it under.
    /// - Returns: The API status response.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
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

    /// Rates a sound on behalf of the authenticated user.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Parameters:
    ///   - soundID: The sound's identifier.
    ///   - rating: The rating, from `0` to `5` inclusive.
    /// - Returns: The API status response.
    /// - Throws: ``FreesoundError/invalidInput(_:)`` if `rating` is out of range,
    ///   ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or another
    ///   ``FreesoundError`` if the request fails.
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

    /// Posts a comment on a sound as the authenticated user.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Parameters:
    ///   - soundID: The sound's identifier.
    ///   - comment: The comment text.
    /// - Returns: The API status response.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
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

    /// Fetches a user's public profile.
    /// - Parameter username: The user's username.
    /// - Returns: The ``User`` profile.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func user(username: String) async throws -> User {
        try await send(path: "/users/\(encodedPathComponent(username))/")
    }

    /// Fetches the sounds uploaded by a user.
    /// - Parameters:
    ///   - username: The user's username.
    ///   - parameters: Optional query parameters such as `fields`, `page`, `page_size`.
    /// - Returns: A page of the user's ``Sound`` uploads.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func userSounds(username: String, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        try await send(path: "/users/\(encodedPathComponent(username))/sounds/", query: parameters)
    }

    /// Fetches the packs created by a user.
    /// - Parameters:
    ///   - username: The user's username.
    ///   - parameters: Optional pagination parameters such as `page`, `page_size`.
    /// - Returns: A page of the user's ``Pack`` values.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func userPacks(username: String, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Pack>
    {
        try await send(path: "/users/\(encodedPathComponent(username))/packs/", query: parameters)
    }

    // MARK: - Packs

    /// Fetches metadata for a pack.
    /// - Parameter id: The pack's identifier.
    /// - Returns: The ``Pack``.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func pack(id: Int) async throws -> Pack {
        try await send(path: "/packs/\(id)/")
    }

    /// Fetches the sounds contained in a pack.
    /// - Parameters:
    ///   - id: The pack's identifier.
    ///   - parameters: Optional query parameters such as `fields`, `page`, `page_size`.
    /// - Returns: A page of the pack's ``Sound`` values.
    /// - Throws: ``FreesoundError`` if the request fails.
    public func packSounds(id: Int, parameters: [String: String?] = [:]) async throws
        -> PagedResponse<Sound>
    {
        try await send(path: "/packs/\(id)/sounds/", query: parameters)
    }

    /// Downloads a pack as a single archive.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``; an API key is not sufficient.
    /// - Parameter id: The pack's identifier.
    /// - Returns: The raw archive data.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
    public func downloadPack(id: Int) async throws -> Data {
        try await sendData(path: "/packs/\(id)/download/", requiresOAuth: true)
    }

    // MARK: - Me / bookmarks

    /// Fetches the authenticated user's own profile.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Returns: The ``Me`` profile.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
    public func me() async throws -> Me {
        try await send(path: "/me/", requiresOAuth: true)
    }

    /// Lists the authenticated user's bookmark categories.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Parameter parameters: Optional pagination parameters such as `page`, `page_size`.
    /// - Returns: A page of ``BookmarkCategory`` values.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
    public func myBookmarkCategories(parameters: [String: String?] = [:]) async throws
        -> PagedResponse<BookmarkCategory>
    {
        try await send(path: "/me/bookmark_categories/", query: parameters, requiresOAuth: true)
    }

    /// Lists the sounds in one of the authenticated user's bookmark categories.
    ///
    /// Requires an ``FreesoundAuthentication/oauthToken(_:)``.
    /// - Parameters:
    ///   - categoryID: The bookmark category's identifier.
    ///   - parameters: Optional query parameters such as `fields`, `page`, `page_size`.
    /// - Returns: A page of bookmarked ``Sound`` values.
    /// - Throws: ``FreesoundError/oauthRequired`` if not OAuth-authenticated, or
    ///   another ``FreesoundError`` if the request fails.
    public func myBookmarkCategorySounds(categoryID: Int, parameters: [String: String?] = [:])
        async throws -> PagedResponse<Sound>
    {
        try await send(
            path: "/me/bookmark_categories/\(categoryID)/sounds/", query: parameters,
            requiresOAuth: true)
    }

    // MARK: - OAuth2 helpers

    /// Builds the authorization URL that begins the OAuth2 authorization-code flow.
    ///
    /// Direct the user to the returned URL; after they approve, Freesound
    /// redirects back with a `code` you exchange via
    /// ``exchangeAuthorizationCode(clientID:clientSecret:code:)``.
    /// - Parameters:
    ///   - clientID: Your application's client identifier.
    ///   - responseState: An optional opaque value echoed back on redirect to guard against CSRF.
    ///   - redirectURI: The redirect URI to return to, if overriding the app's default.
    ///   - forceLogin: When `true`, forces the user to log in again before authorizing.
    /// - Returns: The authorization URL to open.
    /// - Throws: ``FreesoundError`` if the URL cannot be constructed.
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

    /// Exchanges an authorization code for an access and refresh token.
    ///
    /// Call this with the `code` returned to your redirect URI after the user
    /// approves the ``oauthAuthorizationURL(clientID:responseState:redirectURI:forceLogin:)``.
    /// The request is sent unauthenticated regardless of the client's current credential.
    /// - Parameters:
    ///   - clientID: Your application's client identifier.
    ///   - clientSecret: Your application's client secret.
    ///   - code: The authorization code received on redirect.
    /// - Returns: The token response, including access and refresh tokens.
    /// - Throws: ``FreesoundError`` if the request fails.
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

    /// Obtains a fresh access token using a refresh token.
    ///
    /// Freesound access tokens expire; use the refresh token from a prior
    /// exchange to get a new one, then update ``authentication``. The request
    /// is sent unauthenticated regardless of the client's current credential.
    /// - Parameters:
    ///   - clientID: Your application's client identifier.
    ///   - clientSecret: Your application's client secret.
    ///   - refreshToken: The refresh token from a prior token response.
    /// - Returns: The token response, including a new access and refresh token.
    /// - Throws: ``FreesoundError`` if the request fails.
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
        try await send(
            url: buildURL(path: path, query: query),
            method: method,
            body: body,
            contentType: contentType,
            requiresOAuth: requiresOAuth,
            authenticationOverride: authenticationOverride
        )
    }

    private func send<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        requiresOAuth: Bool = false,
        authenticationOverride: FreesoundAuthentication? = nil
    ) async throws -> T {
        let auth = authenticationOverride ?? authentication
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        try applyAuth(auth: auth, requiresOAuth: requiresOAuth, to: &request)

        let data = try await perform(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FreesoundError.decodingError(error)
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
        try await sendData(
            url: buildURL(path: path, query: query),
            method: method,
            body: body,
            contentType: contentType,
            requiresOAuth: requiresOAuth
        )
    }

    private func sendData(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        requiresOAuth: Bool = false,
        applyAuthentication: Bool = true
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if applyAuthentication {
            try applyAuth(auth: authentication, requiresOAuth: requiresOAuth, to: &request)
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FreesoundError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapAPIError(response: httpResponse, data: data)
            }
            return data
        } catch let error as FreesoundError {
            throw error
        } catch {
            throw FreesoundError.transportError(error)
        }
    }

    /// Reads the file on a Dispatch thread so a large blocking read doesn't
    /// stall the cooperative thread pool.
    private static func readFile(at url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try Data(contentsOf: url) })
            }
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

    private func mapAPIError(response: HTTPURLResponse, data: Data) -> FreesoundError {
        struct ErrorPayload: Decodable {
            let detail: String?
        }

        let detail = (try? decoder.decode(ErrorPayload.self, from: data))?.detail ?? "Unknown error"
        if response.statusCode == 429 {
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter, detail: detail)
        }
        return .apiError(statusCode: response.statusCode, detail: detail)
    }

    /// Resolves an API pagination link, which may be absolute (`next`-style)
    /// or a server-relative path (combined search's `more`).
    private func resolveLink(_ link: String) throws -> URL {
        guard let url = URL(string: link, relativeTo: baseURL) else {
            throw FreesoundError.invalidInput("Cannot resolve pagination link: \(link)")
        }
        return url.absoluteURL
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
