//
//  FreesoundSearchFilter.swift
//  FreesoundKit
//
//  A typed builder for the Freesound search `filter` parameter, which on the
//  wire is a raw Solr/Lucene filter expression. This type produces correctly
//  quoted/escaped clauses and ANDs them together, so callers don't hand-write
//  Solr syntax. Pass the result as the `filter` value to
//  ``FreesoundClient/textSearch(query:parameters:)``:
//
//      let filter: SoundFilter = .username("reinsamba") && .duration(min: 5, max: 30)
//      try await client.textSearch(query: "rain", parameters: ["filter": filter.expression])
//
//  Every `field:` clause is forced to a MUST (AND) by the server, so combining
//  clauses always narrows. Use ``SoundFilter/init(raw:)`` for anything this
//  builder doesn't model (e.g. OR groups), and ``SoundFilter/&&(_:_:)`` /
//  ``SoundFilter/all(_:)`` to compose.
//

import Foundation

/// A composable, correctly-escaped Freesound search filter.
///
/// Construct clauses with the static factory methods and combine them with
/// ``&&(_:_:)`` or ``all(_:)``. The underlying string is exposed as
/// ``expression`` for passing to the `filter` query parameter.
public struct SoundFilter: Sendable, Equatable, Hashable, CustomStringConvertible {
  /// The raw Solr/Lucene filter expression, ready for the `filter` parameter.
  public let expression: String

  /// Wraps a raw, already-valid Solr filter expression verbatim — an escape
  /// hatch for clauses this builder does not model (e.g. `tag:(rain OR storm)`).
  public init(raw expression: String) {
    self.expression = expression
  }

  public var description: String { expression }
}

// MARK: - Composition

extension SoundFilter {
  /// ANDs several filters into one (the server treats every clause as a MUST).
  /// An empty input yields an empty expression that matches everything.
  public static func all(_ filters: [SoundFilter]) -> SoundFilter {
    SoundFilter(raw: filters.map(\.expression).filter { !$0.isEmpty }.joined(separator: " "))
  }

  /// ANDs two filters, e.g. `.isGeotagged() && .type("wav")`.
  public static func && (lhs: SoundFilter, rhs: SoundFilter) -> SoundFilter {
    .all([lhs, rhs])
  }
}

// MARK: - Equality & boolean clauses

extension SoundFilter {
  /// Matches the sound whose raw-file MD5 equals `hash` — an exact
  /// file-fingerprint lookup (a single hex value identifies at most one sound).
  public static func md5(_ hash: String) -> SoundFilter {
    SoundFilter(raw: "md5:\(quote(hash))")
  }

  /// Matches sounds uploaded by `username`.
  public static func username(_ username: String) -> SoundFilter {
    SoundFilter(raw: "username:\(quote(username))")
  }

  /// Matches sounds carrying `tag` (exact tag token, not full-text).
  public static func tag(_ tag: String) -> SoundFilter {
    SoundFilter(raw: "tag:\(quote(tag))")
  }

  /// Matches sounds whose license name equals `license` (e.g.
  /// `"Creative Commons 0"`). See ``SoundLicense`` for the canonical strings.
  public static func license(_ license: String) -> SoundFilter {
    SoundFilter(raw: "license:\(quote(license))")
  }

  /// Matches sounds of a given file `type` (e.g. `"wav"`, `"flac"`, `"mp3"`).
  public static func type(_ type: String) -> SoundFilter {
    SoundFilter(raw: "type:\(quote(type))")
  }

  /// Matches sounds belonging to the pack with the given numeric ID
  /// (see ``Sound/packID``).
  ///
  /// The index has no bare pack-ID field; packs are stored as `pack_grouping`
  /// (`"{id}_{name}"`), so this matches the `"{id}_*"` prefix — precise to the
  /// pack ID without needing its name.
  public static func pack(id: Int) -> SoundFilter {
    SoundFilter(raw: "pack_grouping:\(id)_*")
  }

  /// Matches sounds in any pack whose **name** equals `name`. Note pack names are
  /// not unique across users, so this can span multiple packs; use
  /// ``pack(id:)`` to target one specific pack.
  public static func pack(named name: String) -> SoundFilter {
    SoundFilter(raw: "pack:\(quote(name))")
  }

  /// Matches sounds that do (or, with `false`, do not) have a geotag.
  public static func isGeotagged(_ value: Bool = true) -> SoundFilter {
    SoundFilter(raw: "is_geotagged:\(value)")
  }

  /// Matches sounds flagged explicit (or, with `false`, not).
  public static func isExplicit(_ value: Bool = true) -> SoundFilter {
    SoundFilter(raw: "is_explicit:\(value)")
  }

  /// Matches remixes (or, with `false`, non-remixes).
  public static func isRemix(_ value: Bool = true) -> SoundFilter {
    SoundFilter(raw: "is_remix:\(value)")
  }
}

// MARK: - Numeric range clauses

extension SoundFilter {
  /// Duration in seconds. Pass either or both bounds; omitting one leaves it open.
  public static func duration(min: Double? = nil, max: Double? = nil) -> SoundFilter {
    range("duration", min, max)
  }

  /// File size in bytes.
  public static func filesize(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("filesize", min, max)
  }

  /// Number of downloads.
  public static func numDownloads(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("num_downloads", min, max)
  }

  /// Number of ratings.
  public static func numRatings(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("num_ratings", min, max)
  }

  /// Average rating (0–5).
  public static func avgRating(min: Double? = nil, max: Double? = nil) -> SoundFilter {
    range("avg_rating", min, max)
  }

  /// Number of comments.
  public static func numComments(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("num_comments", min, max)
  }

  /// Sample rate in Hz.
  public static func samplerate(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("samplerate", min, max)
  }

  /// Bit depth (e.g. 16, 24).
  public static func bitdepth(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("bitdepth", min, max)
  }

  /// Bit rate in kbps.
  public static func bitrate(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("bitrate", min, max)
  }

  /// Channel count (1 = mono, 2 = stereo, …).
  public static func channels(min: Int? = nil, max: Int? = nil) -> SoundFilter {
    range("channels", min, max)
  }

  /// Upload-date range. Pass either or both bounds.
  public static func created(from: Date? = nil, to: Date? = nil) -> SoundFilter {
    range("created", from.map(solrDate), to.map(solrDate))
  }
}

// MARK: - Geospatial & descriptor clauses

extension SoundFilter {
  /// Matches geotagged sounds within a latitude/longitude bounding box.
  ///
  /// Uses the Solr range form the Freesound geo field expects
  /// (`geotag:["minLat,minLon" TO "maxLat,maxLon"]`). Latitudes are −90…90 and
  /// longitudes −180…180; the caller is responsible for ordering min ≤ max.
  public static func geotagWithin(
    minLatitude: Double, maxLatitude: Double,
    minLongitude: Double, maxLongitude: Double
  ) -> SoundFilter {
    SoundFilter(
      raw: "geotag:[\"\(minLatitude),\(minLongitude)\" TO \"\(maxLatitude),\(maxLongitude)\"]")
  }

  /// Matches an audio-analysis descriptor by an exact string value, such as
  /// `.descriptor("ac_tonality_s", equals: "major")`.
  ///
  /// - Important: Descriptors are Solr *dynamic* fields, so pass the **full field
  ///   name including its type suffix** — `_s` (string), `_d` (double), `_b`
  ///   (bool), `_i` (int) — e.g. `ac_tonality_s`, not `ac_tonality` (the bare
  ///   name is an "undefined field" error). Descriptor population varies by
  ///   analyzer and may be empty for a given deployment, so a well-formed filter
  ///   can still match nothing.
  public static func descriptor(_ field: String, equals value: String) -> SoundFilter {
    SoundFilter(raw: "\(field):\(quote(value))")
  }

  /// Matches a numeric audio-analysis descriptor within a range, such as
  /// `.descriptor("ac_loudness_d", min: -30, max: -10)`. Pass the full dynamic
  /// field name including its `_d`/`_i` suffix — see ``descriptor(_:equals:)``.
  public static func descriptor(_ field: String, min: Double? = nil, max: Double? = nil)
    -> SoundFilter
  {
    range(field, min, max)
  }
}

// MARK: - Internals

extension SoundFilter {
  /// Quotes and escapes a string value for a Solr term (`"…"` with `\` and `"`
  /// escaped), so values containing spaces or special characters are safe.
  private static func quote(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  /// Builds a `field:[lo TO hi]` clause, substituting `*` for an open bound.
  /// Returns an empty filter when both bounds are nil (matches everything).
  private static func range<T: CustomStringConvertible>(
    _ field: String, _ min: T?, _ max: T?
  ) -> SoundFilter {
    guard min != nil || max != nil else { return SoundFilter(raw: "") }
    let lo = min.map(\.description) ?? "*"
    let hi = max.map(\.description) ?? "*"
    return SoundFilter(raw: "\(field):[\(lo) TO \(hi)]")
  }

  /// Formats a `Date` as the UTC Solr timestamp `yyyy-MM-dd'T'HH:mm:ss'Z'`.
  private static func solrDate(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
      c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
  }
}
