//
//  FreesoundKitTests.swift
//  FreesoundKitTests
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation
import FreesoundKit
import Synchronization
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

@Test func meDecodesAvatarObjectAndProfileFields() async throws {
  let mockSession = MockHTTPClient { _ in
    let responseJSON = """
      {
        "url": "https://freesound.org/people/blankie.rest/",
        "username": "blankie.rest",
        "about": "hello",
        "home_page": "https://blankie.rest",
        "avatar": {
          "small": "https://freesound.org/data/avatars/15820/15820073_S.jpg",
          "medium": "https://freesound.org/data/avatars/15820/15820073_M.jpg",
          "large": "https://freesound.org/data/avatars/15820/15820073_L.jpg"
        },
        "date_joined": "2024-03-21T23:48:08.384002+01:00",
        "num_sounds": 1,
        "sounds": "https://freesound.org/apiv2/users/blankie.rest/sounds/",
        "num_packs": 0,
        "packs": "https://freesound.org/apiv2/users/blankie.rest/packs/",
        "num_posts": 0,
        "num_comments": 1,
        "ai_preference": "freesound-cc-recommendation",
        "email": "user@example.com",
        "unique_id": 15820073,
        "bookmark_categories": "https://freesound.org/apiv2/me/bookmark_categories/"
      }
      """
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let me = try await client.me()
  #expect(me.username == "blankie.rest")
  #expect(me.homepage == URL(string: "https://blankie.rest"))
  #expect(
    me.avatar?.large
      == URL(string: "https://freesound.org/data/avatars/15820/15820073_L.jpg"))
  #expect(me.email == "user@example.com")
  #expect(me.uniqueID == 15_820_073)
  #expect(me.numComments == 1)
  #expect(
    me.bookmarkCategories
      == URL(string: "https://freesound.org/apiv2/me/bookmark_categories/"))
  #expect(me.dateJoined == "2024-03-21T23:48:08.384002+01:00")
}

@Test func decodesFieldsConfirmedAgainstLiveAPI() throws {
  // Fields present in real API responses but previously unmodeled (verified
  // against the live API and the Freesound server serializers).
  let soundJSON = #"""
    {"id": 14854, "name": "Nightingale song.wav", "pack": "https://freesound.org/apiv2/packs/455/", "pack_name": "nightingales", "samplerate": 48000.0}
    """#
  let sound = try JSONDecoder().decode(Sound.self, from: Data(soundJSON.utf8))
  #expect(sound.packName == "nightingales")
  #expect(sound.samplerate == 48000.0)  // server FloatField — decoded as Double, not Int

  let packJSON = #"{"id": 455, "name": "nightingales", "num_sounds": 12, "num_downloads": 3456}"#
  let pack = try JSONDecoder().decode(Pack.self, from: Data(packJSON.utf8))
  #expect(pack.numDownloads == 3456)

  let userJSON = #"""
    {"username": "reinsamba", "home_page": "", "num_comments": 54, "ai_preference": "freesound-cc-recommendation",
     "avatar": {"small": "https://freesound.org/data/avatars/18/18799_S.jpg", "medium": null, "large": null}}
    """#
  let user = try JSONDecoder().decode(User.self, from: Data(userJSON.utf8))
  #expect(user.homepage == nil)  // "" -> nil
  #expect(user.numComments == 54)
  #expect(user.aiPreference == "freesound-cc-recommendation")
  #expect(user.avatar?.small != nil)
  #expect(user.avatar?.medium == nil)
}

@Test func soundAnalysisDecodesNewDescriptors() throws {
  // Shapes taken verbatim from a live /sounds/<id>/analysis/ response.
  let json = #"""
    {
      "category": "Sound effects", "subcategory": "Animals",
      "tonality": "B major", "warmth": null, "zero_crossing_rate": 0.139,
      "has_audio_problems": false, "tristimulus": [0.672, 0.261, 0.061],
      "birdnet_detected_class": ["Common Nightingale"],
      "birdnet_detections": [
        {"start_time": 0.0, "end_time": 27.0, "confidence": 1.0,
         "common_name": "Common Nightingale", "scientific_name": "Luscinia megarhynchos"}
      ],
      "birdnet_detections_count": 12,
      "fsdsinet_detected_class": ["Animal"],
      "fsdsinet_detections": [{"name": "Animal", "start_time": 0.0, "end_time": 9.5, "confidence": 0.91}],
      "fsdsinet_detections_count": 134,
      "freesound_classic": [0.81, -0.1], "laion_clap": [-0.016, -0.001]
    }
    """#
  let d = try JSONDecoder().decode(SoundAnalysis.self, from: Data(json.utf8)).descriptors
  #expect(d.category == "Sound effects")
  #expect(d.hasAudioProblems == false)
  #expect(d.warmth == nil)
  #expect(d.birdnetDetectionsCount == 12)
  #expect(d.birdnetDetections?.first?.commonName == "Common Nightingale")
  #expect(d.birdnetDetections?.first?.scientificName == "Luscinia megarhynchos")
  #expect(d.fsdsinetDetections?.first?.name == "Animal")
  #expect(d.fsdsinetDetections?.first?.confidence == 0.91)
  #expect(d.laionClap?.count == 2)
}

@Test func soundDecodesSimPrefixedEmbeddings() throws {
  // The Sound serializer emits similarity embeddings `sim_`-prefixed (unlike the
  // /analysis/ endpoint). They must still land on the unprefixed descriptor fields.
  let json = #"""
    {"id":7,"sim_laion_clap":[0.1,0.2,0.3],"sim_freesound_classic":[0.4,0.5]}
    """#
  let sound = try JSONDecoder().decode(Sound.self, from: Data(json.utf8))
  #expect(sound.descriptors.laionClap == [0.1, 0.2, 0.3])
  #expect(sound.descriptors.freesoundClassic == [0.4, 0.5])
  // Encoding must write the canonical unprefixed key, never the sim_ spelling —
  // assert on the JSON itself (decoding again would mask it, since the decoder
  // accepts both spellings).
  let encoded = String(decoding: try JSONEncoder().encode(sound), as: UTF8.self)
  #expect(encoded.contains("\"laion_clap\""))
  #expect(!encoded.contains("sim_laion_clap"))
}

@Test func meToleratesEmptyHomePageAndAvatarlessAccount() async throws {
  // The serializer emits "" (not null) for an unset home_page, and an avatar
  // object whose three sizes are all null when the user has no avatar. Neither
  // shape should fail the decode (previously both threw a typeMismatch).
  let mockSession = MockHTTPClient { _ in
    let responseJSON = """
      {
        "username": "nobody",
        "url": "https://freesound.org/people/nobody/",
        "about": "",
        "home_page": "",
        "avatar": {"small": null, "medium": null, "large": null}
      }
      """
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let me = try await client.me()
  #expect(me.homepage == nil)
  #expect(me.avatar != nil)
  #expect(me.avatar?.small == nil)
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

@Test func authorizationURLIncludesRequestedScopes() throws {
  let client = FreesoundClient(session: MockHTTPClient.unused)
  let url = try client.oauthAuthorizationURL(clientID: "abc123", scopes: [.read])
  // Space-separated per OAuth2; the single space form-encodes to %20 or '+'.
  let absolute = url.absoluteString
  #expect(absolute.contains("scope=read"))
  #expect(!absolute.contains("write"))

  let rw = try client.oauthAuthorizationURL(clientID: "abc123", scopes: [.read, .write])
  #expect(rw.absoluteString.contains("scope=read"))
  #expect(rw.absoluteString.contains("write"))

  // Omitting scopes sends none (server applies its default).
  let none = try client.oauthAuthorizationURL(clientID: "abc123")
  #expect(!none.absoluteString.contains("scope="))
}

@Test func passwordGrantSendsResourceOwnerCredentials() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/oauth2/access_token")
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("grant_type=password"))
    #expect(body.contains("username=alice"))
    #expect(body.contains("password=secret"))
    return (
      Data(
        #"{"access_token":"a1","token_type":"Bearer","expires_in":86399,"refresh_token":"r1"}"#
          .utf8), makeResponse()
    )
  }
  let client = FreesoundClient(session: mockSession)
  let token = try await client.exchangePasswordGrant(
    clientID: "id", clientSecret: "secret", username: "alice", password: "secret")
  #expect(token.accessToken == "a1")
  #expect(token.tokenType == "Bearer")
}

@Test func oauthTokenEndpointErrorIsStructured() async throws {
  // The token endpoint's {"error","error_description"} envelope maps to .oauthError,
  // not a generic .apiError, so callers can branch on `invalid_grant`.
  let mockSession = MockHTTPClient { _ in
    (
      Data(#"{"error":"invalid_grant","error_description":"Token has expired."}"#.utf8),
      makeResponse(status: 401)
    )
  }
  let client = FreesoundClient(session: mockSession)
  do {
    _ = try await client.refreshAccessToken(
      clientID: "id", clientSecret: "secret", refreshToken: "stale")
    Issue.record("Expected oauthError")
  } catch let error as FreesoundError {
    guard case .oauthError(let code, let description, let statusCode) = error else {
      Issue.record("Expected oauthError, got \(error)")
      return
    }
    #expect(code == "invalid_grant")
    #expect(description == "Token has expired.")
    #expect(statusCode == 401)
  }
}

@Test func throttleScopeParsesServerMessage() {
  #expect(
    FreesoundError.rateLimited(
      retryAfter: nil, detail: "exceeding a request limit rate (60/minute)"
    )
    .throttleScope == .perMinute)
  #expect(
    FreesoundError.rateLimited(retryAfter: nil, detail: "exceeding a request limit rate (2000/day)")
      .throttleScope == .perDay)
  #expect(
    FreesoundError.rateLimited(retryAfter: nil, detail: "exceeding a request limit rate (100/hour)")
      .throttleScope == .perHour)
  #expect(
    FreesoundError.rateLimited(
      retryAfter: nil, detail: "the ApiV2 credential has been suspended"
    ).throttleScope
      == .suspended)
  // Unrecognized throttle message -> nil (so withRateLimitRetry still retries it).
  #expect(
    FreesoundError.rateLimited(retryAfter: nil, detail: "Request was throttled").throttleScope
      == nil)
  #expect(FreesoundError.apiError(statusCode: 400, detail: "x").throttleScope == nil)
}

@Test func rateLimitRetryRetriesPerMinuteThrottle() async throws {
  // A per-minute throttle clears within the minute, so it must be retried (and
  // succeed on a later attempt), unlike the per-day case below.
  let attempts = Mutex(0)
  let client = FreesoundClient(session: MockHTTPClient.unused)
  let result = try await client.withRateLimitRetry(maxAttempts: 3, fallbackDelay: 0) {
    let n = attempts.withLock {
      $0 += 1
      return $0
    }
    if n < 2 {
      throw FreesoundError.rateLimited(
        retryAfter: nil, detail: "exceeding a request limit rate (60/minute)")
    }
    return "ok"
  }
  #expect(result == "ok")
  #expect(attempts.withLock { $0 } == 2)
}

@Test func rateLimitRetryDoesNotRetryPerDayThrottle() async throws {
  // A per-day throttle won't clear on a short retry, so it must be rethrown after
  // the first attempt rather than slept-and-retried.
  let attempts = Mutex(0)
  let client = FreesoundClient(session: MockHTTPClient.unused)
  await #expect(throws: FreesoundError.self) {
    try await client.withRateLimitRetry(maxAttempts: 3, fallbackDelay: 0) {
      attempts.withLock { $0 += 1 }
      throw FreesoundError.rateLimited(
        retryAfter: nil, detail: "exceeding a request limit rate (2000/day)")
    }
  }
  #expect(attempts.withLock { $0 } == 1)
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

// The test itself is marked deprecated so the one intentional call to the
// deprecated `bookmarkSound(soundID:name:category:)` overload compiles without
// a warning.
@available(*, deprecated)
@Test func bookmarkDoesNotSendNameFieldTheAPIIgnores() async throws {
  let mockSession = MockHTTPClient { request in
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    // The deprecated `name:` argument must not reach the wire — the Freesound
    // bookmark serializer only reads `category`.
    #expect(!body.contains("name="))
    #expect(body.contains("category=favorites"))
    return (Data(#"{"detail":"ok"}"#.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.bookmarkSound(
    soundID: 99, name: "My favorite", category: "favorites")
  #expect(response.detail == "ok")
}

@Test func soundSearchSortRawValuesMatchAPIStrings() {
  #expect(SoundSearchSort.score.rawValue == "score")
  #expect(SoundSearchSort.downloadsDescending.rawValue == "downloads_desc")
  #expect(SoundSearchSort.ratingAscending.rawValue == "rating_asc")
  #expect(SoundSearchSort.allCases.count == 9)
}

@Test func groupedSearchDecodesPackGroupingAndNote() async throws {
  let json = #"""
    {"count":1,"next":null,"previous":null,"note":"Query was adjusted.",
     "results":[{"id":7,"name":"kick","score":12.5,
       "more_from_same_pack":"https://freesound.org/apiv2/search/text/?filter=pack_grouping:%2241_drums%22",
       "n_from_same_pack":4,"distance_to_target":0.42}]}
    """#
  let mockSession = MockHTTPClient { _ in (Data(json.utf8), makeResponse()) }
  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)

  let page = try await client.textSearch(query: "kick", parameters: ["group_by_pack": "1"])
  #expect(page.note == "Query was adjusted.")
  let sound = try #require(page.results.first)
  #expect(sound.nFromSamePack == 4)
  #expect(sound.distanceToTarget == 0.42)
  #expect(sound.moreFromSamePack?.path == "/apiv2/search/text")

  // The grouping fields survive a Codable round-trip and are absent on a plain sound.
  let roundTripped = try JSONDecoder().decode(Sound.self, from: JSONEncoder().encode(sound))
  #expect(roundTripped == sound)
  let plain = try JSONDecoder().decode(Sound.self, from: Data(#"{"id":7}"#.utf8))
  #expect(plain.nFromSamePack == nil)
  #expect(plain.moreFromSamePack == nil)
}

@Test func soundLicenseRawValuesMatchAPIChoices() {
  // The server's LICENSE_CHOICES are an exact-match set, so the spellings matter.
  #expect(SoundLicense.attribution.rawValue == "Attribution")
  #expect(SoundLicense.attributionNonCommercial.rawValue == "Attribution NonCommercial")
  #expect(SoundLicense.creativeCommons0.rawValue == "Creative Commons 0")
  #expect(SoundLicense.allCases.count == 3)
}

@Test func describeSendsLicenseRawValueAndCommaSeparatedGeotag() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/apiv2/sounds/describe")
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("upload_filename=clip.wav"))
    // License raw value flows through (space-encoded as '+').
    #expect(body.contains("license=Creative+Commons+0"))
    // bst_category is optional on describe but set here, so it is sent.
    #expect(body.contains("bst_category=fx-other"))
    // Geotag keeps its comma-separated write format ('+'-free, comma as %2C).
    #expect(body.contains("geotag=41.4%2C2.18%2C16"))
    return (Data(#"{"detail":"ok"}"#.utf8), makeResponse(status: 201))
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.describeSound(
    request: SoundDescribeRequest(
      uploadFilename: "clip.wav",
      tags: ["one", "two", "three"],
      description: "A clip",
      license: .creativeCommons0,
      bstCategory: "fx-other",
      geotag: "41.4,2.18,16"))
  #expect(response.detail == "ok")
}

@Test func editSoundUsesOAuthAndSendsOnlySetFields() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/apiv2/sounds/42/edit")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("name=New+title"))
    #expect(body.contains("tags=field+recording+nature"))
    // Unset fields must not be sent (partial update).
    #expect(!body.contains("description="))
    #expect(!body.contains("license="))
    let responseJSON = #"{"detail":"ok"}"#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.editSound(
    soundID: 42,
    request: SoundEditRequest(name: "New title", tags: ["field", "recording", "nature"])
  )
  #expect(response.detail == "ok")
}

@Test func describeSoundDecodesNewSoundID() async throws {
  // The describe endpoint's 201 returns {detail, id}; the id must survive on
  // APIStatusResponse since it's the only place a described sound's id appears.
  let mockSession = MockHTTPClient { request in
    // bst_category is optional on describe and unset here, so it must be omitted.
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(!body.contains("bst_category"))
    return (
      Data(#"{"detail":"Sound successfully described.","id":98765}"#.utf8),
      makeResponse(status: 201)
    )
  }
  let client = FreesoundClient(authentication: .oauthToken("t"), session: mockSession)
  let response = try await client.describeSound(
    request: SoundDescribeRequest(
      uploadFilename: "c.wav", tags: ["one", "two", "three"], description: "d",
      license: .creativeCommons0))
  #expect(response.id == 98765)
  #expect(response.detail == "Sound successfully described.")
}

@Test func tagCountValidatedClientSideBeforeSending() async throws {
  // Fewer than 3 tags is rejected locally (like rateSound's range guard), so the
  // request never reaches the network.
  let client = FreesoundClient(
    authentication: .oauthToken("t"), session: MockHTTPClient.unused)
  await #expect(throws: FreesoundError.self) {
    try await client.describeSound(
      request: SoundDescribeRequest(
        uploadFilename: "c.wav", tags: ["only-one"], description: "d", license: .attribution))
  }
  // Same guard on the upload path (too few) and edit path (too many) — the guard
  // runs before the network, so the unused session is never touched.
  await #expect(throws: FreesoundError.self) {
    try await client.uploadSound(
      fileURL: URL(fileURLWithPath: "/does-not-exist.wav"),
      request: SoundUploadRequest(
        tags: ["one", "two"], description: "d", license: .attribution, bstCategory: "fx-other"))
  }
  await #expect(throws: FreesoundError.self) {
    try await client.editSound(
      soundID: 1, request: SoundEditRequest(tags: Array(repeating: "t", count: 31)))
  }
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

@Test func soundAnalysisFetchesFullAnalysisWithoutQuery() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/sounds/7/analysis")
    // The endpoint ignores query params; we send none.
    #expect(request.url?.query == nil)
    return (Data(#"{"loudness":-23.1,"single_event":true}"#.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let analysis = try await client.soundAnalysis(id: 7)

  #expect(analysis.descriptors.loudness == -23.1)
  #expect(analysis.descriptors.singleEvent == true)
}

@Test func downloadOriginalSoundReturnsRawData() async throws {
  let audio = Data([0x00, 0x01, 0x02, 0x03])
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/sounds/7/download")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
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

@Test func soundDownloadLinkUsesOAuthAndDecodesURL() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/apiv2/sounds/7/download/link")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    let json = #"{"download_link":"https://freesound.org/apiv2/download/abc.token/"}"#
    return (Data(json.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let link = try await client.soundDownloadLink(id: 7)
  #expect(link.downloadLink == URL(string: "https://freesound.org/apiv2/download/abc.token/"))
}

@Test func soundDownloadLinkRequiresOAuth() async throws {
  let client = FreesoundClient(authentication: .apiKey("k"), session: MockHTTPClient.unused)
  do {
    _ = try await client.soundDownloadLink(id: 7)
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
    // The describe path requires bst_category, so it must be in the body.
    #expect(bodyString.contains("name=\"bst_category\""))
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
      tags: ["one", "two", "three"], description: "A test clip", license: .creativeCommons0,
      bstCategory: "fx-other")
  )
  #expect(response.id == 123)
}

@Test func uploadEscapesSpecialCharactersInFilename() async throws {
  // A double-quote is legal in a filename on macOS/Linux; it must be escaped so
  // it can't terminate the quoted-string `filename="..."` parameter.
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("a\"b-\(UUID().uuidString).wav")
  let fileBytes = Data([0x52, 0x49, 0x46, 0x46])
  try fileBytes.write(to: fileURL)
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let mockSession = MockHTTPClient { request in
    let bodyString = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    #expect(bodyString.contains("filename=\"a\\\"b-"))
    let responseJSON = #"{"id":1,"detail":"File successfully uploaded"}"#
    return (Data(responseJSON.utf8), makeResponse(status: 201))
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  _ = try await client.uploadSound(
    fileURL: fileURL,
    request: SoundUploadRequest(
      tags: ["one", "two", "three"], description: "A test clip", license: .creativeCommons0,
      bstCategory: "fx-other"))
}

@Test func multiWordTagsJoinWithDashesAndDoNotSplit() async throws {
  let mockSession = MockHTTPClient { request in
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    // "field recording" is one tag (internal space -> dash); separate tags stay
    // space-delimited (form-encoded as '+').
    #expect(body.contains("tags=field-recording+nature+outdoor"))
    return (Data(#"{"detail":"ok"}"#.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.editSound(
    soundID: 7,
    request: SoundEditRequest(tags: ["field recording", "nature", "outdoor"])
  )
  #expect(response.detail == "ok")
}

@Test func nonJSONErrorBodySurfacesRawBody() async throws {
  // A non-JSON body (e.g. an upstream gateway's text/HTML page) is surfaced raw
  // rather than swallowed as "Unknown error".
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
    #expect(detail == "gateway timeout")
  }
}

@Test func emptyErrorBodyFallsBackToUnknownDetail() async throws {
  let mockSession = MockHTTPClient { _ in (Data(), makeResponse(status: 500)) }
  let client = FreesoundClient(session: mockSession)

  do {
    _ = try await client.textSearch(query: "bird")
    Issue.record("Expected API error")
  } catch let error as FreesoundError {
    guard case .apiError(_, let detail) = error else {
      Issue.record("Expected apiError, got \(error)")
      return
    }
    #expect(detail == "Unknown error")
  }
}

@Test func validationErrorDetailFlattensFieldMessages() async throws {
  // The write endpoints return {"detail": {<field>: [msgs]}} on 400; the
  // field-level messages must survive rather than collapsing to "Unknown error".
  let body = #"{"detail":{"description":["This field is required."]}}"#
  let mockSession = MockHTTPClient { _ in
    (Data(body.utf8), makeResponse(status: 400))
  }
  let client = FreesoundClient(authentication: .oauthToken("t"), session: mockSession)

  do {
    _ = try await client.describeSound(
      request: SoundDescribeRequest(
        uploadFilename: "c.wav", tags: ["a", "b", "c"],
        description: "d", license: .creativeCommons0, bstCategory: "fx-other"))
    Issue.record("Expected API error")
  } catch let error as FreesoundError {
    guard case .apiError(let statusCode, let detail) = error else {
      Issue.record("Expected apiError, got \(error)")
      return
    }
    #expect(statusCode == 400)
    #expect(detail == "description: This field is required.")
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
      responseJSON =
        #"{"count":2,"next":null,"previous":"\#(page1URL)","results":[{"id":2}]}"#
    } else {
      responseJSON =
        #"{"count":2,"next":"\#(page2URL)","previous":null,"results":[{"id":1}]}"#
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

@Test func similaritySearchUsesSimilarToParameter() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/search/text")
    let query = request.url?.query ?? ""
    #expect(query.contains("similar_to=14854"))
    // The server's form field is `similarity_space`; `similar_space` is silently
    // dropped (it would fall back to the default space without error).
    #expect(query.contains("similarity_space=laion_clap"))
    #expect(!query.contains("similar_space="))
    return (
      Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":99}]}"#.utf8), makeResponse()
    )
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let page = try await client.similaritySearch(toSoundID: 14854, space: .laionClap)
  #expect(page.results.first?.id == 99)
}

@Test func similaritySearchSendsNonDefaultSpace() async throws {
  // Regression for the `similar_space` → `similarity_space` key fix: a non-default
  // space must actually reach the server, not be silently coerced to the default.
  let mockSession = MockHTTPClient { request in
    let query = request.url?.query ?? ""
    #expect(query.contains("similarity_space=freesound_classic"))
    return (
      Data(#"{"count":0,"next":null,"previous":null,"results":[]}"#.utf8), makeResponse()
    )
  }
  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  _ = try await client.similaritySearch(toSoundID: 14854, space: .freesoundClassic)
}

@Test func similaritySearchByVectorSerializesSimilarTo() async throws {
  let mockSession = MockHTTPClient { request in
    let query = request.url?.query?.removingPercentEncoding ?? ""
    // The embedding is sent as a JSON array (5-decimal components) via similar_to.
    #expect(query.contains("similar_to=[0.10000,-0.20000,0.30000]"))
    #expect(query.contains("similarity_space=laion_clap"))
    return (
      Data(#"{"count":0,"next":null,"previous":null,"results":[]}"#.utf8), makeResponse()
    )
  }
  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  _ = try await client.similaritySearch(toVector: [0.1, -0.2, 0.3], space: .laionClap)
}

// Marked deprecated so it can exercise the deprecated methods without warnings.
@available(*, deprecated)
@Test func removedSearchEndpointsThrowClearError() async throws {
  let client = FreesoundClient(authentication: .apiKey("k"), session: MockHTTPClient.unused)
  do {
    _ = try await client.contentSearch(parameters: ["target": "x"])
    Issue.record("contentSearch should throw")
  } catch is FreesoundError {
  }
  do {
    _ = try await client.combinedSearch(parameters: ["target": "x"])
    Issue.record("combinedSearch should throw")
  } catch is FreesoundError {
  }
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

@Test func parsesFreesoundTimestamps() async throws {
  // Sound timestamps carry milliseconds; user timestamps do not. Both are
  // timezone-less and interpreted as UTC.
  let sound = try JSONDecoder().decode(
    Sound.self, from: Data(#"{"id":1,"created":"2014-04-16T20:07:11.145"}"#.utf8))
  let user = try JSONDecoder().decode(
    User.self,
    from: Data(#"{"username":"alice","date_joined":"2008-08-07T17:39:00"}"#.utf8))

  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = TimeZone(secondsFromGMT: 0)!

  let createdComponents = utc.dateComponents(
    [.year, .month, .day, .hour, .minute, .second, .nanosecond],
    from: try #require(sound.createdDate))
  #expect(createdComponents.year == 2014)
  #expect(createdComponents.month == 4)
  #expect(createdComponents.day == 16)
  #expect(createdComponents.hour == 20)
  #expect(createdComponents.minute == 7)
  #expect(createdComponents.second == 11)
  // The fractional-seconds strategy must preserve the ".145" millisecond part.
  let nanos = try #require(createdComponents.nanosecond)
  #expect(abs(nanos - 145_000_000) < 1_000_000)

  let joinedComponents = utc.dateComponents(
    [.year, .hour, .minute], from: try #require(user.dateJoinedDate))
  #expect(joinedComponents.year == 2008)
  #expect(joinedComponents.hour == 17)
  #expect(joinedComponents.minute == 39)

  // The same helper backs Comment, Pack, and PendingUpload; verify each wires
  // it to the right field rather than trusting only the Sound/User paths.
  #expect(Comment(created: "2014-04-16T20:07:11.145").createdDate != nil)
  #expect(Pack(id: 1, created: "2014-04-16T20:07:11.145").createdDate != nil)
  #expect(PendingUpload(created: "2008-08-07T17:39:00").createdDate != nil)
}

@Test func unparsableTimestampYieldsNil() {
  #expect(Sound(id: 1, created: "not a date").createdDate == nil)
  #expect(Sound(id: 1, created: nil).createdDate == nil)
}

@Test func modelsAreIdentifiableAndEquatable() {
  let a = Sound(id: 7, name: "Kick")
  let b = Sound(id: 7, name: "Kick")
  let c = Sound(id: 7, name: "Snare")
  #expect(a == b)
  #expect(a != c)
  #expect(a.id == 7)
  // Hashable: equal values hash equally; usable as Set/dictionary keys.
  #expect(Set([a, b, c]).count == 2)

  // Identifiable via username for user models.
  #expect(User(username: "alice").id == "alice")
  #expect(Me(username: "bob").id == "bob")
}

@Test func rateLimitRetrySucceedsAfterThrottle() async throws {
  let attempts = Mutex(0)
  let result = try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
    maxAttempts: 3, fallbackDelay: 0, maxDelay: 0
  ) {
    let attempt = attempts.withLock {
      $0 += 1
      return $0
    }
    if attempt < 3 {
      throw FreesoundError.rateLimited(retryAfter: nil, detail: "throttled")
    }
    return attempt
  }
  #expect(result == 3)
  #expect(attempts.withLock { $0 } == 3)
}

@Test func rateLimitRetryGivesUpAfterMaxAttempts() async throws {
  let attempts = Mutex(0)
  do {
    _ =
      try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
        maxAttempts: 2, fallbackDelay: 0, maxDelay: 0
      ) {
        attempts.withLock { $0 += 1 }
        throw FreesoundError.rateLimited(retryAfter: nil, detail: "throttled")
      } as Int
    Issue.record("Expected rateLimited to be rethrown")
    return
  } catch let error as FreesoundError {
    guard case .rateLimited = error else {
      Issue.record("Expected rateLimited, got \(error)")
      return
    }
  }
  #expect(attempts.withLock { $0 } == 2)
}

@Test func rateLimitRetryDoesNotSwallowOtherErrors() async throws {
  let attempts = Mutex(0)
  do {
    _ =
      try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry {
        attempts.withLock { $0 += 1 }
        throw FreesoundError.oauthRequired
      } as Int
    Issue.record("Expected oauthRequired to be rethrown")
    return
  } catch let error as FreesoundError {
    guard case .oauthRequired = error else {
      Issue.record("Expected oauthRequired, got \(error)")
      return
    }
  }
  // Non-rate-limit errors are not retried.
  #expect(attempts.withLock { $0 } == 1)
}

@Test func rateLimitRetryWaitsForRetryAfter() async throws {
  // Exercises the delay path the other retry tests skip: a non-nil Retry-After
  // is extracted, clamped, and actually slept through before the next attempt.
  let clock = ContinuousClock()
  let attempts = Mutex(0)
  let start = clock.now
  let result = try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
    maxAttempts: 2, fallbackDelay: 0, maxDelay: 60
  ) {
    let attempt = attempts.withLock {
      $0 += 1
      return $0
    }
    if attempt == 1 {
      throw FreesoundError.rateLimited(retryAfter: 0.05, detail: "throttled")
    }
    return attempt
  }
  #expect(result == 2)
  #expect(clock.now - start >= .milliseconds(40))
}

@Test func rateLimitRetryHonorsCancellationWithoutDelay() async throws {
  let attempts = Mutex(0)
  let task = Task {
    try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
      maxAttempts: 1_000_000, fallbackDelay: 0, maxDelay: 0
    ) {
      attempts.withLock { $0 += 1 }
      throw FreesoundError.rateLimited(retryAfter: nil, detail: "throttled")
    } as Int
  }
  task.cancel()
  do {
    _ = try await task.value
    Issue.record("Expected cancellation to propagate")
    return
  } catch is CancellationError {
    // expected: the loop checks cancellation between attempts even with no
    // delay, so it stops far short of its million-attempt ceiling.
  }
  #expect(attempts.withLock { $0 } < 1_000_000)
}

@Test func rateLimitRetryRejectsNonPositiveMaxAttempts() async throws {
  do {
    _ =
      try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
        maxAttempts: 0
      ) {
        42
      } as Int
    Issue.record("Expected invalidInput to be thrown")
    return
  } catch let error as FreesoundError {
    guard case .invalidInput = error else {
      Issue.record("Expected invalidInput, got \(error)")
      return
    }
  }
}

// MARK: - Codable round-trips (models are now persistable to disk)

@Test func soundRoundTripsThroughCodable() throws {
  let json = #"""
    {"id":7,"name":"Kick","url":"https://freesound.org/s/7/","tags":["drum","kick"],
     "license":"https://creativecommons.org/publicdomain/zero/1.0/","type":"wav",
     "duration":0.5,"category":"Music","subcategory":"Percussion","category_code":"mu-perc",
     "previews":{"preview-hq-mp3":"https://freesound.org/data/previews/7/7_hq.mp3"},
     "images":{"waveform_m":"https://freesound.org/data/displays/7/7_wave_M.png"},
     "num_downloads":10,"avg_rating":4.5,"num_ratings":6,"num_comments":2,"score":98.5,
     "brightness":42.5,"bpm":120,"loopable":true,"tonality":"C minor",
     "beat_times":[0.1,0.2],"note_name":"C3"}
    """#
  let original = try JSONDecoder().decode(Sound.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(Sound.self, from: JSONEncoder().encode(original))
  // Exact equality covers every keyed field AND the flattened descriptors.
  #expect(roundTripped == original)
  #expect(roundTripped.score == 98.5)
  #expect(roundTripped.descriptors.bpm == 120)
  #expect(roundTripped.descriptors.beatTimes == [0.1, 0.2])
  #expect(roundTripped.previews?.previewHQMP3 != nil)
  #expect(roundTripped.images?.waveformM != nil)
}

@Test func soundAnalysisRoundTripsThroughCodable() throws {
  let original = try JSONDecoder().decode(
    SoundAnalysis.self, from: Data(#"{"loudness":-23.1,"single_event":true,"bpm":90}"#.utf8))
  let roundTripped = try JSONDecoder().decode(
    SoundAnalysis.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.descriptors.loudness == -23.1)
  #expect(roundTripped.descriptors.singleEvent == true)
}

@Test func meRoundTripsThroughCodable() throws {
  // Exercises the lenient-URL fields: synthesized encoding writes URLs as the strings the custom
  // decoder reads back, so the round-trip must be exact.
  let json = """
    {"url":"https://freesound.org/people/blankie.rest/","username":"blankie.rest",
     "about":"hello","home_page":"https://blankie.rest",
     "avatar":{"small":"https://freesound.org/data/avatars/1/1_S.jpg",
               "medium":"https://freesound.org/data/avatars/1/1_M.jpg",
               "large":"https://freesound.org/data/avatars/1/1_L.jpg"},
     "date_joined":"2024-03-21T23:48:08.384002+01:00","num_sounds":1,
     "sounds":"https://freesound.org/apiv2/users/blankie.rest/sounds/","num_packs":0,
     "num_comments":1,"email":"user@example.com","unique_id":15820073,
     "bookmark_categories":"https://freesound.org/apiv2/me/bookmark_categories/"}
    """
  let original = try JSONDecoder().decode(Me.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(Me.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.homepage == URL(string: "https://blankie.rest"))
  #expect(
    roundTripped.avatar?.large == URL(string: "https://freesound.org/data/avatars/1/1_L.jpg"))
}

@Test func userRoundTripsThroughCodable() throws {
  // `home_page:""` exercises the lenient-URL path: the empty string decodes to nil, so the
  // re-encoded JSON omits the key and the second decode must land on the same nil value.
  let json = """
    {"username":"sampleuser","url":"https://freesound.org/people/sampleuser/",
     "about":"hi","home_page":"","ai_preference":"allow",
     "avatar":{"small":"https://freesound.org/data/avatars/2/2_S.jpg","medium":null,"large":null},
     "date_joined":"2024-03-21T23:48:08.384002+01:00","num_sounds":3,"num_packs":1,
     "num_posts":2,"sounds":"https://freesound.org/apiv2/users/sampleuser/sounds/",
     "packs":"https://freesound.org/apiv2/users/sampleuser/packs/","num_comments":4}
    """
  let original = try JSONDecoder().decode(User.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.homepage == nil)
  #expect(roundTripped.avatar?.small == URL(string: "https://freesound.org/data/avatars/2/2_S.jpg"))
  #expect(roundTripped.avatar?.medium == nil)
}

@Test func realAPIResponseRoundTripsThroughCodable() throws {
  // Captured verbatim from a live GET /sounds/14854/?fields=...,bpm,loudness,beat_times,tonality,
  // single_event,birdnet_detections,fsdsinet_detections (beat_times truncated). Proves an actual
  // server response — flattened descriptors, dash-keyed previews, CDN preview URLs, nested
  // detection arrays — survives decode → encode → decode by value.
  let json = #"""
    {"id":14854,"name":"reinsamba at the nightingales feet 2.wav",
     "url":"https://freesound.org/people/reinsamba/sounds/14854/",
     "tags":["field-recording","nightingale","nature","bird"],
     "license":"https://creativecommons.org/licenses/by/4.0/","type":"wav","duration":136.515,
     "category":"Soundscapes","subcategory":"Animals",
     "previews":{"preview-hq-mp3":"https://cdn.freesound.org/previews/14/14854_18799-hq.mp3",
                 "preview-hq-ogg":"https://cdn.freesound.org/previews/14/14854_18799-hq.ogg",
                 "preview-lq-mp3":"https://cdn.freesound.org/previews/14/14854_18799-lq.mp3",
                 "preview-lq-ogg":"https://cdn.freesound.org/previews/14/14854_18799-lq.ogg"},
     "images":{"waveform_l":"https://cdn.freesound.org/displays/14/14854_18799_wave_L.png",
               "waveform_m":"https://cdn.freesound.org/displays/14/14854_18799_wave_M.png",
               "spectral_l":"https://cdn.freesound.org/displays/14/14854_18799_spec_L.jpg",
               "spectral_m":"https://cdn.freesound.org/displays/14/14854_18799_spec_M.jpg"},
     "num_downloads":50871,"avg_rating":4.5,"bpm":135,"brightness":null,"loudness":-20.71,
     "beat_times":[0.476,0.952,1.428,1.904],"tonality":"B major","single_event":false,
     "birdnet_detections":[{"end_time":27.0,"confidence":1.0,"start_time":0.0,
                            "common_name":"Common Nightingale","scientific_name":"Luscinia megarhynchos"}],
     "fsdsinet_detections":[{"name":"Animal","end_time":9.5,"confidence":0.91,"start_time":0.0}]}
    """#
  let original = try JSONDecoder().decode(Sound.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(Sound.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  // Spot-check that the flattened descriptors and shared category keys survived intact.
  #expect(roundTripped.category == "Soundscapes")
  #expect(roundTripped.descriptors.bpm == 135)
  #expect(roundTripped.descriptors.tonality == "B major")
  #expect(roundTripped.descriptors.beatTimes == [0.476, 0.952, 1.428, 1.904])
  #expect(roundTripped.descriptors.birdnetDetections?.first?.commonName == "Common Nightingale")
  #expect(roundTripped.descriptors.fsdsinetDetections?.first?.name == "Animal")
  #expect(roundTripped.previews?.previewHQMP3?.host == "cdn.freesound.org")
}

@Test func pagedResponseOfSoundRoundTripsThroughCodable() throws {
  // Verifies the conditional `Encodable where Item: Encodable` conformance.
  let json = #"""
    {"count":2,"next":null,"previous":null,
     "results":[{"id":1,"name":"One"},{"id":2,"name":"Two","bpm":100}]}
    """#
  let original = try JSONDecoder().decode(PagedResponse<Sound>.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(
    PagedResponse<Sound>.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.results.last?.descriptors.bpm == 100)
}

@Test func pagedResponseDropsNullResultsInsteadOfFailing() throws {
  // The search/similarity endpoints append JSON `null` for index-desynced sounds.
  // The whole page must survive, with the nulls dropped — not throw and lose all.
  let json = #"""
    {"count":3,"next":null,"previous":null,"results":[{"id":1},null,{"id":3}]}
    """#
  let page = try JSONDecoder().decode(PagedResponse<Sound>.self, from: Data(json.utf8))
  #expect(page.results.map(\.id) == [1, 3])
  #expect(page.count == 3)
}

@Test func pendingUploadDecodesRealMinimalSoundShape() throws {
  // The server returns a minimal sound dict, not a full Sound: id/name/tags/
  // description/created/license, plus processing_state (pending processing) and
  // images (pending moderation).
  let json = #"""
    {"pending_description":["a.wav","b.aiff"],
     "pending_processing":[{"id":1,"name":"P","tags":["x"],"description":"d",
       "created":"2008-08-07T17:39:00","license":"https://creativecommons.org/publicdomain/zero/1.0/",
       "processing_state":"Processing"}],
     "pending_moderation":[{"id":2,"name":"M","tags":["y"],"description":"d2",
       "created":"2008-08-07T17:39:00","license":"https://creativecommons.org/licenses/by/4.0/",
       "images":{"waveform_m":"https://freesound.org/data/displays/2/2_wave_M.png"}}]}
    """#
  let pending = try JSONDecoder().decode(PendingUploads.self, from: Data(json.utf8))
  #expect(pending.pendingDescription == ["a.wav", "b.aiff"])
  let processing = pending.pendingProcessing.first
  #expect(processing?.id == 1)
  #expect(processing?.name == "P")
  #expect(processing?.tags == ["x"])
  #expect(processing?.processingState == "Processing")
  #expect(processing?.createdDate != nil)
  let moderation = pending.pendingModeration.first
  #expect(moderation?.images?.waveformM != nil)
  #expect(moderation?.processingState == nil)
}

// MARK: - Value-enum Codable (so consumer structs holding them synthesize Codable)

/// Encodes `value` inside an array (sidestepping top-level-fragment limits) and
/// returns the single string it serialized to.
private func encodedToken<T: Codable>(_ value: T) throws -> String {
  try JSONDecoder().decode([String].self, from: JSONEncoder().encode([value]))[0]
}

@Test func stringRawValueEnumsEncodeAsAPITokens() throws {
  // Free synthesis: these encode as the exact API token, not the Swift case name.
  #expect(try encodedToken(SoundSearchSort.downloadsDescending) == "downloads_desc")
  #expect(try encodedToken(SoundLicense.creativeCommons0) == "Creative Commons 0")
  #expect(try encodedToken(SimilaritySpace.laionClap) == "laion_clap")
}

@Test func selectorEnumsEncodeAsStableTokens() throws {
  // Custom single-value Codable: stable tokens, not the synthesized `{"case":{}}` shape.
  #expect(try encodedToken(SoundPreviewFormat.hqMP3) == "hq-mp3")
  #expect(try encodedToken(SoundImageType.waveformL) == "waveform_l")
  #expect(try encodedToken(AvatarSize.medium) == "medium")
  #expect(try encodedToken(APIUsageKind.write) == "write")
}

@Test func valueEnumsRoundTripEveryCase() throws {
  func roundTrip<T: Codable & Equatable & CaseIterable>(_ type: T.Type) throws {
    let all = Array(T.allCases)
    let back = try JSONDecoder().decode([T].self, from: JSONEncoder().encode(all))
    #expect(back == all)
  }
  try roundTrip(SoundSearchSort.self)
  try roundTrip(SoundLicense.self)
  try roundTrip(SimilaritySpace.self)
  try roundTrip(SoundPreviewFormat.self)
  try roundTrip(SoundImageType.self)
  try roundTrip(AvatarSize.self)
  try roundTrip(APIUsageKind.self)
}

@Test func selectorEnumRejectsUnknownToken() {
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode([SoundImageType].self, from: Data(#"["bogus"]"#.utf8))
  }
}

@Test func structHoldingValueEnumsSynthesizesCodable() throws {
  // The consumer need: a persisted struct mixing value enums round-trips losslessly
  // without any `@retroactive Codable` workaround.
  struct SavedSearch: Codable, Equatable {
    var sort: SoundSearchSort
    var space: SimilaritySpace
    var license: SoundLicense
    var preview: SoundPreviewFormat
    var image: SoundImageType
    var avatar: AvatarSize
  }
  let original = SavedSearch(
    sort: .ratingDescending, space: .freesoundClassic, license: .attributionNonCommercial,
    preview: .lqOGG, image: .spectralM, avatar: .large)
  let back = try JSONDecoder().decode(SavedSearch.self, from: JSONEncoder().encode(original))
  #expect(back == original)
}

// MARK: - Image download

@Test func downloadImageFetchesImageWithoutAuth() async throws {
  let imageURLString = "https://cdn.freesound.org/displays/7/7_1_wave_M.png"
  let soundJSON = #"{"id":7,"images":{"waveform_m":"\#(imageURLString)"}}"#
  let sound = try JSONDecoder().decode(Sound.self, from: Data(soundJSON.utf8))

  let png = Data([0x89, 0x50, 0x4E, 0x47])
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.absoluteString == imageURLString)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    return (png, makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let data = try await client.downloadImage(for: sound, type: .waveformM)
  #expect(data == png)
}

@Test func downloadImageWithoutImagesThrowsInvalidInput() async throws {
  let sound = try JSONDecoder().decode(Sound.self, from: Data(#"{"id":7}"#.utf8))
  let client = FreesoundClient(session: MockHTTPClient.unused)
  do {
    _ = try await client.downloadImage(for: sound, type: .spectralL)
    Issue.record("Expected invalidInput error")
  } catch let error as FreesoundError {
    guard case .invalidInput = error else {
      Issue.record("Expected invalidInput, got \(error)")
      return
    }
  }
}

// MARK: - FreesoundAssetCache

@Test func assetCacheFetchesOnceThenServesFromDisk() async throws {
  let dir = uniqueTempDirectory()
  defer { try? FileManager.default.removeItem(at: dir) }
  let counter = CallCounter()
  let payload = Data([0x01, 0x02, 0x03])
  let cache = FreesoundAssetCache(directory: dir, maxByteSize: 0) { _ in
    await counter.increment()
    return payload
  }
  let url = URL(string: "https://cdn.freesound.org/previews/7/7-hq.mp3")!

  let first = try await cache.data(for: url)
  let second = try await cache.data(for: url)

  #expect(first == payload)
  #expect(second == payload)
  #expect(await counter.count == 1)  // second call served from disk
  #expect(await cache.contains(url))
}

@Test func assetCacheDeDuplicatesConcurrentFetches() async throws {
  let dir = uniqueTempDirectory()
  defer { try? FileManager.default.removeItem(at: dir) }
  let counter = CallCounter()
  let gate = TestGate()
  let payload = Data([0xAA])
  let cache = FreesoundAssetCache(directory: dir, maxByteSize: 0) { _ in
    await counter.increment()
    await gate.markStarted()
    await gate.waitUntilOpen()
    return payload
  }
  let url = URL(string: "https://cdn.freesound.org/previews/9/9-hq.mp3")!

  async let a = cache.data(for: url)
  await gate.waitUntilStarted()  // the one fetch is now in flight and registered
  async let b = cache.data(for: url)
  async let c = cache.data(for: url)
  await gate.open()

  let results = try await [a, b, c]
  #expect(results.allSatisfy { $0 == payload })
  #expect(await counter.count == 1)  // three concurrent reads, a single download
}

@Test func assetCacheEvictsLeastRecentlyUsedOverBudget() async throws {
  let dir = uniqueTempDirectory()
  defer { try? FileManager.default.removeItem(at: dir) }
  let payload = Data(repeating: 0x7, count: 6)  // each asset is 6 bytes
  let cache = FreesoundAssetCache(directory: dir, maxByteSize: 10) { _ in payload }
  let first = URL(string: "https://cdn.freesound.org/a")!
  let second = URL(string: "https://cdn.freesound.org/b")!

  _ = try await cache.data(for: first)
  try await Task.sleep(for: .milliseconds(10))  // ensure `first` is the older entry
  _ = try await cache.data(for: second)  // 12 > 10 budget → evict `first`

  #expect(await cache.contains(second))
  #expect(!(await cache.contains(first)))
  #expect(await cache.totalDiskBytes() <= 10)
}

@Test func assetCacheCachesAvatars() async throws {
  let dir = uniqueTempDirectory()
  defer { try? FileManager.default.removeItem(at: dir) }
  let counter = CallCounter()
  let png = Data([0x89, 0x50])
  let cache = FreesoundAssetCache(directory: dir, maxByteSize: 0) { _ in
    await counter.increment()
    return png
  }
  let avatar = try JSONDecoder().decode(
    Avatar.self,
    from: Data(#"{"large":"https://cdn.freesound.org/avatars/1/1_L.jpg"}"#.utf8))

  let bytes = try await cache.avatarData(for: avatar, size: .large)
  _ = try await cache.avatarData(for: avatar, size: .large)

  #expect(bytes == png)
  #expect(await counter.count == 1)
}

@Test func assetCacheCachesUserAndMeAvatars() async throws {
  let dir = uniqueTempDirectory()
  defer { try? FileManager.default.removeItem(at: dir) }
  let counter = CallCounter()
  let png = Data([0x89, 0x50])
  let cache = FreesoundAssetCache(directory: dir, maxByteSize: 0) { _ in
    await counter.increment()
    return png
  }
  let avatarJSON = #"{"medium":"https://cdn.freesound.org/avatars/2/2_M.jpg"}"#
  let user = try JSONDecoder().decode(
    User.self, from: Data(#"{"username":"u","avatar":\#(avatarJSON)}"#.utf8))
  let me = try JSONDecoder().decode(
    Me.self, from: Data(#"{"username":"u","avatar":\#(avatarJSON)}"#.utf8))

  // Both overloads resolve to the same avatar URL, so the second is a disk hit.
  #expect(try await cache.avatarData(for: user) == png)
  #expect(try await cache.avatarData(for: me) == png)
  #expect(await counter.count == 1)
}

@Test func assetCacheUserWithoutAvatarThrowsInvalidInput() async throws {
  let dir = uniqueTempDirectory()
  defer { try? FileManager.default.removeItem(at: dir) }
  let cache = FreesoundAssetCache(directory: dir, maxByteSize: 0) { _ in Data() }
  let user = try JSONDecoder().decode(User.self, from: Data(#"{"username":"u"}"#.utf8))
  do {
    _ = try await cache.avatarData(for: user)
    Issue.record("Expected invalidInput error")
  } catch let error as FreesoundError {
    guard case .invalidInput = error else {
      Issue.record("Expected invalidInput, got \(error)")
      return
    }
  }
}

#if canImport(Observation)
  @MainActor
  @Test func usageMonitorSnapshotsTrackerAndRefreshes() {
    let tracker = FreesoundUsageTracker(limits: .level1)
    tracker.record(.standard)
    let monitor = FreesoundUsageMonitor(tracker, refresh: .seconds(60))
    defer { monitor.stop() }

    #expect(monitor.snapshot.standard.usedToday == 1)

    tracker.record(.standard)
    tracker.record(.write)
    // The timer hasn't ticked yet; refreshNow re-reads immediately.
    monitor.refreshNow()
    #expect(monitor.snapshot.standard.usedToday == 2)
    #expect(monitor.snapshot.write.usedToday == 1)
  }
#endif

// MARK: - Avatar monograms

@Test func monogramMatchesFreesoundSelection() {
  // index = (ord(s0) + ord(s1)) % 10 for multi-char names. "reinsamba": 114+101=215 → 5.
  let monogram = AvatarMonogram(username: "reinsamba")
  #expect(monogram.letter == "R")
  #expect(monogram.backgroundColor == AvatarMonogram.palette[5])
  #expect(monogram.backgroundColor == RGBColor(red: 170, green: 206, blue: 65))
}

@Test func monogramUsesFirstCharForSingleCharacterNames() {
  // Single character → ord(s0) % 10. "a" = 97 → 7.
  let monogram = AvatarMonogram(username: "a")
  #expect(monogram.letter == "A")
  #expect(monogram.backgroundColor == AvatarMonogram.palette[7])
}

@Test func monogramUsesSourceTruncatedPalette() {
  // "ai": 97+105=202 → index 2. The byte-exact server value is (9,199,113) — the
  // truncated interpolation, not a rounded (10,200,114).
  #expect(AvatarMonogram.palette.count == 10)
  #expect(AvatarMonogram(username: "ai").backgroundColor == RGBColor(red: 9, green: 199, blue: 113))
}

@Test func monogramHandlesEmptyUsername() {
  let monogram = AvatarMonogram(username: "")
  #expect(monogram.letter == "?")
  #expect(monogram.backgroundColor == nil)
}

@Test func userAndMeExposeMonograms() throws {
  let user = try JSONDecoder().decode(User.self, from: Data(#"{"username":"reinsamba"}"#.utf8))
  let me = try JSONDecoder().decode(Me.self, from: Data(#"{"username":"reinsamba"}"#.utf8))
  #expect(user.monogram == AvatarMonogram(username: "reinsamba"))
  #expect(me.monogram == AvatarMonogram(username: "reinsamba"))
  #expect(user.monogram.backgroundColor?.fractions.red == 170.0 / 255)
}

// MARK: - Usage tracking

@Test func usageTrackerCountsWithinRollingWindows() {
  let tracker = FreesoundUsageTracker(limits: .level1)
  let now = Date(timeIntervalSince1970: 1_000_000)
  tracker.record(.standard, at: now.addingTimeInterval(-90))  // outside the minute
  tracker.record(.standard, at: now.addingTimeInterval(-30))  // inside the minute
  tracker.record(.standard, at: now.addingTimeInterval(-5))  // inside the minute
  tracker.record(.write, at: now.addingTimeInterval(-10))

  #expect(tracker.count(.standard, within: 60, asOf: now) == 2)
  #expect(tracker.count(.standard, within: 24 * 3600, asOf: now) == 3)
  #expect(tracker.count(.write, within: 60, asOf: now) == 1)
}

@Test func usageTrackerSnapshotReportsRemaining() {
  let tracker = FreesoundUsageTracker(limits: .level1)
  let now = Date(timeIntervalSince1970: 2_000_000)
  for index in 0..<5 { tracker.record(.standard, at: now.addingTimeInterval(-Double(index))) }
  tracker.record(.write, at: now.addingTimeInterval(-2))

  let snapshot = tracker.snapshot(asOf: now)
  #expect(snapshot.standard.usedThisMinute == 5)
  #expect(snapshot.standard.remainingThisMinute == 55)  // 60 - 5
  #expect(snapshot.standard.remainingToday == 1995)  // 2000 - 5
  #expect(snapshot.write.usedThisMinute == 1)
  #expect(snapshot.write.remainingThisMinute == 29)  // 30 - 1
}

@Test func usageTrackerPrunesAndPersistsEvents() {
  let tracker = FreesoundUsageTracker()
  let now = Date(timeIntervalSince1970: 3_000_000)
  tracker.record(.standard, at: now.addingTimeInterval(-90_000))  // > 24h: pruned on record
  tracker.record(.standard, at: now.addingTimeInterval(-100))

  // Persistence round-trip: events survive into a fresh tracker.
  let restored = FreesoundUsageTracker(standardEvents: tracker.events(.standard))
  #expect(restored.count(.standard, within: 24 * 3600, asOf: now) == 1)
}

@Test func clientRecordsStandardReadUsage() async throws {
  let tracker = FreesoundUsageTracker()
  let mock = MockHTTPClient { _ in
    (Data(#"{"count":0,"results":[]}"#.utf8), makeResponse())
  }
  let client = FreesoundClient(
    authentication: .apiKey("k"), session: mock, usageTracker: tracker)

  _ = try await client.textSearch(query: "rain")
  #expect(tracker.count(.standard, within: 60) == 1)
  #expect(tracker.count(.write, within: 60) == 0)
}

@Test func clientRecordsWriteUsageForPostActions() async throws {
  let tracker = FreesoundUsageTracker()
  let mock = MockHTTPClient { _ in (Data(#"{"detail":"ok"}"#.utf8), makeResponse()) }
  let client = FreesoundClient(
    authentication: .oauthToken("t"), session: mock, usageTracker: tracker)

  _ = try await client.rateSound(soundID: 7, rating: 5)
  #expect(tracker.count(.write, within: 60) == 1)
  #expect(tracker.count(.standard, within: 60) == 0)
}

@Test func clientDoesNotCountOAuthTokenExchange() async throws {
  let tracker = FreesoundUsageTracker()
  let mock = MockHTTPClient { _ in
    (Data(#"{"access_token":"a","expires_in":1,"refresh_token":"r"}"#.utf8), makeResponse())
  }
  let client = FreesoundClient(session: mock, usageTracker: tracker)

  _ = try await client.exchangeAuthorizationCode(clientID: "c", clientSecret: "s", code: "x")
  // /oauth2/ token calls aren't subject to the APIv2 throttle.
  #expect(tracker.count(.standard, within: 60) == 0)
  #expect(tracker.count(.write, within: 60) == 0)
}

@Test func clientDoesNotCountCDNAssetDownloads() async throws {
  let tracker = FreesoundUsageTracker()
  let soundJSON = #"""
    {"id":7,"previews":{"preview-hq-mp3":"https://cdn.freesound.org/previews/7/7-hq.mp3"}}
    """#
  let sound = try JSONDecoder().decode(Sound.self, from: Data(soundJSON.utf8))
  let mock = MockHTTPClient { _ in (Data([0xFF]), makeResponse()) }
  let client = FreesoundClient(
    authentication: .apiKey("k"), session: mock, usageTracker: tracker)

  _ = try await client.downloadPreview(for: sound)
  // CDN fetches (cdn.freesound.org) aren't APIv2 requests.
  #expect(tracker.count(.standard, within: 60) == 0)
}

private func uniqueTempDirectory() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("FreesoundKitCacheTests-\(UUID().uuidString)")
}

private actor CallCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

/// A two-phase signal for deterministic concurrency tests: the in-flight fetch
/// reports it has *started*, and the test later *opens* the gate to let it finish.
private actor TestGate {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var opened = false
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  func markStarted() {
    started = true
    for waiter in startWaiters { waiter.resume() }
    startWaiters.removeAll()
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func open() {
    opened = true
    for waiter in openWaiters { waiter.resume() }
    openWaiters.removeAll()
  }

  func waitUntilOpen() async {
    if opened { return }
    await withCheckedContinuation { openWaiters.append($0) }
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
