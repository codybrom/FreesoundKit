//
//  FreesoundRequests.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation

/// Encodes a list of tags into the Freesound API's space-delimited `tags` field.
///
/// The API uses spaces as the separator *between* tags and expects multi-word
/// tags to be joined with dashes. Any whitespace *inside* a single tag is
/// therefore converted to a dash — otherwise a tag like `"field recording"`
/// would be silently split into two tags (`field`, `recording`) on the server.
/// Empty or whitespace-only tags are dropped.
func encodeTags(_ tags: [String]) -> String {
  tags
    .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: "-") }
    .filter { !$0.isEmpty }
    .joined(separator: " ")
}

/// Description metadata uploaded alongside an audio file via
/// ``FreesoundClient/uploadSound(fileURL:request:fileFieldName:)``.
///
/// This always uploads *and describes* in one call, so the describe-required
/// fields — ``tags``, ``description``, ``license``, and ``bstCategory`` — are all
/// required (an upload that provides a description but omits the category is a
/// 400). To upload without describing, omit the `request` argument entirely.
public struct SoundUploadRequest: Sendable {
  /// 3–30 tags. Multi-word tags are joined with dashes when encoded (see ``encodeTags(_:)``).
  public var tags: [String]
  public var description: String
  /// The sound's license. The API validates against this exact set.
  public var license: SoundLicense
  /// A Broad Sound Taxonomy subcategory code (e.g. `"m"`/`"fx-..."`). Required on
  /// the describe path; see the Freesound Broad Sound Taxonomy for valid codes.
  public var bstCategory: String
  public var name: String?
  public var pack: String?
  /// Geotag as `"lat,lon,zoom"` — comma-separated, with `lat` ∈ [-90, 90],
  /// `lon` ∈ [-180, 180], and integer `zoom` ≥ 11. Note this differs from the
  /// *read* format (``Sound/geotag`` is space-separated `"lat lon"`), so a value
  /// read back from a ``Sound`` cannot be passed here unchanged.
  public var geotag: String?

  public init(
    tags: [String],
    description: String,
    license: SoundLicense,
    bstCategory: String,
    name: String? = nil,
    pack: String? = nil,
    geotag: String? = nil
  ) {
    self.tags = tags
    self.description = description
    self.license = license
    self.bstCategory = bstCategory
    self.name = name
    self.pack = pack
    self.geotag = geotag
  }

  var asFormFields: [String: String] {
    var fields: [String: String] = [
      "tags": encodeTags(tags),
      "description": description,
      "license": license.rawValue,
      "bst_category": bstCategory,
    ]
    if let name {
      fields["name"] = name
    }
    if let pack {
      fields["pack"] = pack
    }
    if let geotag {
      fields["geotag"] = geotag
    }
    return fields
  }
}

/// Fields to change on an already-described sound via
/// ``FreesoundClient/editSound(soundID:request:)``.
///
/// All fields are optional; only the non-`nil` ones are sent, so the edit is a
/// partial update — unspecified fields keep their current values.
public struct SoundEditRequest: Sendable {
  public var name: String?
  /// 3–30 tags. Replaces the sound's existing tags (it is not additive).
  public var tags: [String]?
  public var description: String?
  /// The sound's license. The API validates against this exact set.
  public var license: SoundLicense?
  /// A Broad Sound Taxonomy subcategory code.
  ///
  /// - Warning: The Freesound *edit* endpoint currently ignores this field — its
  ///   request serializer omits the `bst_category` declaration, so the value is
  ///   dropped server-side (describe/upload accept it normally). It is still sent
  ///   so it takes effect if/when the server adds the field.
  public var bstCategory: String?
  public var pack: String?
  /// Geotag as `"lat,lon,zoom"` (comma-separated, `zoom` ≥ 11). Differs from the
  /// space-separated read format on ``Sound/geotag``.
  public var geotag: String?

  public init(
    name: String? = nil,
    tags: [String]? = nil,
    description: String? = nil,
    license: SoundLicense? = nil,
    bstCategory: String? = nil,
    pack: String? = nil,
    geotag: String? = nil
  ) {
    self.name = name
    self.tags = tags
    self.description = description
    self.license = license
    self.bstCategory = bstCategory
    self.pack = pack
    self.geotag = geotag
  }

  var asFormFields: [String: String] {
    var fields: [String: String] = [:]
    if let name {
      fields["name"] = name
    }
    if let tags {
      fields["tags"] = encodeTags(tags)
    }
    if let description {
      fields["description"] = description
    }
    if let license {
      fields["license"] = license.rawValue
    }
    if let bstCategory {
      fields["bst_category"] = bstCategory
    }
    if let pack {
      fields["pack"] = pack
    }
    if let geotag {
      fields["geotag"] = geotag
    }
    return fields
  }
}

public struct SoundDescribeRequest: Sendable {
  /// Filename of a previously uploaded sound, as returned by `pendingUploads()`.
  public var uploadFilename: String
  /// 3–30 tags. Multi-word tags are joined with dashes when encoded.
  public var tags: [String]
  public var description: String
  /// The sound's license. The API validates against this exact set.
  public var license: SoundLicense
  /// A Broad Sound Taxonomy subcategory code. Optional on the *describe* endpoint
  /// (unlike upload-with-description, where it is required), so it is only sent
  /// when set.
  public var bstCategory: String?
  public var name: String?
  public var pack: String?
  /// Geotag as `"lat,lon,zoom"` (comma-separated, `zoom` ≥ 11). Differs from the
  /// space-separated read format on ``Sound/geotag``.
  public var geotag: String?

  public init(
    uploadFilename: String,
    tags: [String],
    description: String,
    license: SoundLicense,
    bstCategory: String? = nil,
    name: String? = nil,
    pack: String? = nil,
    geotag: String? = nil
  ) {
    self.uploadFilename = uploadFilename
    self.tags = tags
    self.description = description
    self.license = license
    self.bstCategory = bstCategory
    self.name = name
    self.pack = pack
    self.geotag = geotag
  }

  var asFormFields: [String: String] {
    var fields: [String: String] = [
      "upload_filename": uploadFilename,
      "tags": encodeTags(tags),
      "description": description,
      "license": license.rawValue,
    ]
    if let bstCategory {
      fields["bst_category"] = bstCategory
    }
    if let name {
      fields["name"] = name
    }
    if let pack {
      fields["pack"] = pack
    }
    if let geotag {
      fields["geotag"] = geotag
    }
    return fields
  }
}
