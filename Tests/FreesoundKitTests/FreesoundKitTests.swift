//
//  FreesoundKitTests.swift
//  FreesoundKitTests
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation
import FreesoundKit
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Test func textSearchUsesTokenAuthHeader() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.path == "/apiv2/search/text")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token test-key")
        #expect(request.url?.query?.contains("query=piano") == true)

        let responseJSON =
            #"{"count":1,"next":null,"previous":null,"results":[{"id":42,"name":"Piano hit"}]}"#
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .apiKey("test-key"), session: mockSession)
    let result = try await client.textSearch(query: "piano")

    #expect(result.results.count == 1)
    #expect(result.results.first?.id == 42)
}

@Test func oauthEndpointRequiresOAuthToken() async throws {
    let client = FreesoundClient(authentication: .apiKey("token"), session: MockHTTPClient.unused)
    do {
        _ = try await client.me()
        Issue.record("Expected oauthRequired error")
    } catch let error as FreesoundError {
        switch error {
        case .oauthRequired:
            break
        default:
            Issue.record("Expected oauthRequired, got \(error)")
        }
    }
}

@Test func meUsesBearerHeader() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.path == "/apiv2/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")

        let responseJSON =
            #"{"username":"alice","url":"https://freesound.org/people/alice/","about":"hello"}"#
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
    let me = try await client.me()
    #expect(me.username == "alice")
}

@Test func buildsAuthorizationURL() throws {
    let client = FreesoundClient(session: MockHTTPClient.unused)
    let url = try client.oauthAuthorizationURL(
        clientID: "abc123", responseState: "xyz", forceLogin: true)
    let absolute = url.absoluteString
    #expect(absolute.contains("/oauth2/logout_and_authorize/"))
    #expect(absolute.contains("client_id=abc123"))
    #expect(absolute.contains("response_type=code"))
    #expect(absolute.contains("state=xyz"))
}

@Test func exchangesAuthorizationCode() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/apiv2/oauth2/access_token")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=temp-code"))

        let responseJSON =
            #"{"access_token":"a1","scope":"read write","expires_in":86399,"refresh_token":"r1"}"#
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(session: mockSession)
    let token = try await client.exchangeAuthorizationCode(
        clientID: "id", clientSecret: "secret", code: "temp-code")

    #expect(token.accessToken == "a1")
    #expect(token.refreshToken == "r1")
}

@Test func mapsDetailFromAPIError() async throws {
    let mockSession = MockHTTPClient { _ in
        let responseJSON = #"{"detail":"Invalid token"}"#
        return (Data(responseJSON.utf8), makeResponse(status: 400))
    }
    let client = FreesoundClient(session: mockSession)

    do {
        _ = try await client.textSearch(query: "bird")
        Issue.record("Expected API error")
    } catch let error as FreesoundError {
        switch error {
        case .apiError(let statusCode, let detail):
            #expect(statusCode == 400)
            #expect(detail == "Invalid token")
        default:
            Issue.record("Expected apiError, got \(error)")
        }
    }
}

@Test func bookmarkUsesOAuthAndPostBody() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/apiv2/sounds/99/bookmark")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("category=favorites"))
        let responseJSON = #"{"detail":"ok","status":"created"}"#
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
    let response = try await client.bookmarkSound(soundID: 99, category: "favorites")
    #expect(response.detail == "ok")
}

@Test func editSoundUsesOAuthAndSendsOnlySetFields() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/apiv2/sounds/42/edit")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("name=New+title"))
        #expect(body.contains("tags=field+recording"))
        // Unset fields must not be sent (partial update).
        #expect(!body.contains("description="))
        #expect(!body.contains("license="))
        let responseJSON = #"{"detail":"ok"}"#
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
    let response = try await client.editSound(
        soundID: 42,
        request: SoundEditRequest(name: "New title", tags: ["field", "recording"])
    )
    #expect(response.detail == "ok")
}

@Test func ratingValidatesRange() async throws {
    let client = FreesoundClient(
        authentication: .oauthToken("oauth-token"), session: MockHTTPClient.unused)
    do {
        _ = try await client.rateSound(soundID: 1, rating: 9)
        Issue.record("Expected invalidInput")
    } catch let error as FreesoundError {
        switch error {
        case .invalidInput:
            break
        default:
            Issue.record("Expected invalidInput, got \(error)")
        }
    }
}

@Test func soundDecodesFlattenedDescriptors() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.path == "/apiv2/sounds/7")
        let responseJSON = #"""
            {"id":7,"name":"Kick","duration":0.5,
             "brightness":42.5,"bpm":120,"loopable":true,"tonality":"C minor",
             "beat_times":[0.1,0.2],"note_name":"C3"}
            """#
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
    let sound = try await client.sound(id: 7)

    #expect(sound.name == "Kick")
    #expect(sound.duration == 0.5)
    #expect(sound.descriptors.brightness == 42.5)
    #expect(sound.descriptors.bpm == 120)
    #expect(sound.descriptors.loopable == true)
    #expect(sound.descriptors.tonality == "C minor")
    #expect(sound.descriptors.beatTimes == [0.1, 0.2])
    #expect(sound.descriptors.noteName == "C3")
}

@Test func soundAnalysisDecodesDescriptorsAndQuery() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.path == "/apiv2/sounds/7/analysis")
        let query = request.url?.query ?? ""
        #expect(query.contains("descriptors=loudness"))
        #expect(query.contains("normalized=1"))
        return (Data(#"{"loudness":-23.1,"single_event":true}"#.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
    let analysis = try await client.soundAnalysis(id: 7, descriptors: "loudness", normalized: true)

    #expect(analysis.descriptors.loudness == -23.1)
    #expect(analysis.descriptors.singleEvent == true)
}

@Test func downloadOriginalSoundReturnsRawData() async throws {
    let audio = Data([0x00, 0x01, 0x02, 0x03])
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.path == "/apiv2/sounds/7/download")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
        return (audio, makeResponse())
    }

    let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
    let data = try await client.downloadOriginalSound(id: 7)
    #expect(data == audio)
}

@Test func downloadRequiresOAuth() async throws {
    let client = FreesoundClient(authentication: .apiKey("k"), session: MockHTTPClient.unused)
    do {
        _ = try await client.downloadOriginalSound(id: 7)
        Issue.record("Expected oauthRequired error")
    } catch let error as FreesoundError {
        guard case .oauthRequired = error else {
            Issue.record("Expected oauthRequired, got \(error)")
            return
        }
    }
}

@Test func uploadSoundBuildsMultipartBody() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("freesoundkit-test-\(UUID().uuidString).wav")
    let fileBytes = Data([0x52, 0x49, 0x46, 0x46])
    try fileBytes.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let mockSession = MockHTTPClient { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/apiv2/sounds/upload")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = contentType.replacingOccurrences(
            of: "multipart/form-data; boundary=", with: "")
        let body = request.httpBody ?? Data()
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("--\(boundary)\r\n"))
        #expect(bodyString.contains("name=\"description\""))
        #expect(bodyString.contains("filename=\"\(fileURL.lastPathComponent)\""))
        #expect(bodyString.contains("Content-Type: audio/wav"))
        #expect(body.range(of: fileBytes) != nil)
        #expect(bodyString.hasSuffix("--\(boundary)--\r\n"))
        let responseJSON = #"{"id":123,"detail":"File successfully uploaded"}"#
        return (Data(responseJSON.utf8), makeResponse(status: 201))
    }

    let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
    let response = try await client.uploadSound(
        fileURL: fileURL,
        request: SoundUploadRequest(
            tags: ["test"], description: "A test clip", license: "Creative Commons 0")
    )
    #expect(response.id == 123)
}

@Test func nonJSONErrorBodyFallsBackToUnknownDetail() async throws {
    let mockSession = MockHTTPClient { _ in
        (Data("gateway timeout".utf8), makeResponse(status: 502))
    }
    let client = FreesoundClient(session: mockSession)

    do {
        _ = try await client.textSearch(query: "bird")
        Issue.record("Expected API error")
    } catch let error as FreesoundError {
        guard case .apiError(let statusCode, let detail) = error else {
            Issue.record("Expected apiError, got \(error)")
            return
        }
        #expect(statusCode == 502)
        #expect(detail == "Unknown error")
    }
}

@Test func rateLimitedMapsRetryAfter() async throws {
    let mockSession = MockHTTPClient { _ in
        let responseJSON = #"{"detail":"Request was throttled"}"#
        return (
            Data(responseJSON.utf8), makeResponse(status: 429, headers: ["Retry-After": "12"])
        )
    }
    let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)

    do {
        _ = try await client.textSearch(query: "bird")
        Issue.record("Expected rateLimited error")
    } catch let error as FreesoundError {
        guard case .rateLimited(let retryAfter, let detail) = error else {
            Issue.record("Expected rateLimited, got \(error)")
            return
        }
        #expect(retryAfter == 12)
        #expect(detail == "Request was throttled")
    }
}

@Test func decodingFailureCarriesUnderlyingError() async throws {
    let mockSession = MockHTTPClient { _ in
        (Data("not json".utf8), makeResponse())
    }
    let client = FreesoundClient(session: mockSession)

    do {
        _ = try await client.textSearch(query: "bird")
        Issue.record("Expected decodingError")
    } catch let error as FreesoundError {
        guard case .decodingError(let underlying) = error else {
            Issue.record("Expected decodingError, got \(error)")
            return
        }
        #expect(underlying is DecodingError)
    }
}

@Test func nextPageFollowsNextURLWithAuth() async throws {
    let page1URL = "https://freesound.org/apiv2/search/text/?query=piano&page=1"
    let page2URL = "https://freesound.org/apiv2/search/text/?query=piano&page=2"
    let mockSession = MockHTTPClient { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token test-key")
        let responseJSON: String
        if request.url?.query?.contains("page=2") == true {
            responseJSON = #"{"count":2,"next":null,"previous":"\#(page1URL)","results":[{"id":2}]}"#
        } else {
            responseJSON = #"{"count":2,"next":"\#(page2URL)","previous":null,"results":[{"id":1}]}"#
        }
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .apiKey("test-key"), session: mockSession)
    let first = try await client.textSearch(query: "piano")
    #expect(first.results.first?.id == 1)

    let second = try await client.nextPage(of: first)
    #expect(second?.results.first?.id == 2)

    let afterLast = try await client.nextPage(of: second!)
    #expect(afterLast == nil)

    let backToFirst = try await client.previousPage(of: second!)
    #expect(backToFirst?.results.first?.id == 1)
}

@Test func combinedSearchFollowsMoreLink() async throws {
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.path == "/apiv2/search/combined")
        let responseJSON: String
        if request.url?.query?.contains("more=more_token") == true {
            responseJSON = #"{"results":[{"id":2}],"more":null}"#
        } else {
            responseJSON =
                #"{"results":[{"id":1}],"more":"/apiv2/search/combined/?more=more_token"}"#
        }
        return (Data(responseJSON.utf8), makeResponse())
    }

    let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
    let first = try await client.combinedSearch(parameters: ["target": "rhythm.bpm:120"])
    #expect(first.results.first?.id == 1)

    let second = try await client.moreResults(of: first)
    #expect(second?.results.first?.id == 2)

    let third = try await client.moreResults(of: second!)
    #expect(third == nil)
}

@Test func downloadPreviewFetchesPreviewWithoutAuth() async throws {
    let previewURLString = "https://cdn.freesound.org/previews/7/7_1-hq.mp3"
    let soundJSON = #"{"id":7,"previews":{"preview-hq-mp3":"\#(previewURLString)"}}"#
    let sound = try JSONDecoder().decode(Sound.self, from: Data(soundJSON.utf8))

    let audio = Data([0xFF, 0xFB])
    let mockSession = MockHTTPClient { request in
        #expect(request.url?.absoluteString == previewURLString)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        return (audio, makeResponse())
    }

    let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
    let data = try await client.downloadPreview(for: sound)
    #expect(data == audio)
}

@Test func downloadPreviewWithoutPreviewsThrowsInvalidInput() async throws {
    let sound = try JSONDecoder().decode(Sound.self, from: Data(#"{"id":7}"#.utf8))
    let client = FreesoundClient(session: MockHTTPClient.unused)
    do {
        _ = try await client.downloadPreview(for: sound, format: .lqOGG)
        Issue.record("Expected invalidInput error")
    } catch let error as FreesoundError {
        guard case .invalidInput = error else {
            Issue.record("Expected invalidInput, got \(error)")
            return
        }
    }
}

private struct UnexpectedHTTPCall: Error {}

private final class MockHTTPClient: FreesoundHTTPClient, @unchecked Sendable {
    static let unused = MockHTTPClient { _ in
        Issue.record("Unexpected HTTP call")
        throw UnexpectedHTTPCall()
    }

    private let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

private func makeResponse(status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://freesound.org/apiv2/mock/")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
}
