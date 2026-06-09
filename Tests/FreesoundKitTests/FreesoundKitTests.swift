//
//  FreesoundKitTests.swift
//  FreesoundKitTests
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation
import Testing

import FreesoundKit

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

private final class MockHTTPClient: FreesoundHTTPClient, @unchecked Sendable {
    static let unused = MockHTTPClient { _ in
        Issue.record("Unexpected HTTP call")
        throw FreesoundError.transportError("Unexpected HTTP call")
    }

    private let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

private func makeResponse(status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://freesound.org/apiv2/mock/")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}
