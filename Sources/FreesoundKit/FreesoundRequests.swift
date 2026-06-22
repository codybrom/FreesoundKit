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

public struct SoundUploadRequest: Sendable {
  public var tags: [String]
  public var description: String
  public var license: String
  public var name: String?
  public var bstCategory: String?
  public var pack: String?
  public var geotag: String?

  public init(
    tags: [String],
    description: String,
    license: String,
    name: String? = nil,
    bstCategory: String? = nil,
    pack: String? = nil,
    geotag: String? = nil
  ) {
    self.tags = tags
    self.description = description
    self.license = license
    self.name = name
    self.bstCategory = bstCategory
    self.pack = pack
    self.geotag = geotag
  }

  var asFormFields: [String: String] {
    var fields: [String: String] = [
      "tags": encodeTags(tags),
      "description": description,
      "license": license,
    ]
    if let name {
      fields["name"] = name
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

/// Fields to change on an already-described sound via
/// ``FreesoundClient/editSound(soundID:request:)``.
///
/// All fields are optional; only the non-`nil` ones are sent, so the edit is a
/// partial update — unspecified fields keep their current values.
public struct SoundEditRequest: Sendable {
  public var name: String?
  public var tags: [String]?
  public var description: String?
  public var license: String?
  /// Broad Sound Taxonomy category id.
  public var bstCategory: String?
  public var pack: String?
  public var geotag: String?

  public init(
    name: String? = nil,
    tags: [String]? = nil,
    description: String? = nil,
    license: String? = nil,
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
      fields["license"] = license
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
  /// Broad Sound Taxonomy category id (required by the describe endpoint).
  public var bstCategory: String
  public var tags: [String]
  public var description: String
  public var license: String
  public var name: String?
  public var pack: String?
  public var geotag: String?

  public init(
    uploadFilename: String,
    bstCategory: String,
    tags: [String],
    description: String,
    license: String,
    name: String? = nil,
    pack: String? = nil,
    geotag: String? = nil
  ) {
    self.uploadFilename = uploadFilename
    self.bstCategory = bstCategory
    self.tags = tags
    self.description = description
    self.license = license
    self.name = name
    self.pack = pack
    self.geotag = geotag
  }

  var asFormFields: [String: String] {
    var fields: [String: String] = [
      "upload_filename": uploadFilename,
      "bst_category": bstCategory,
      "tags": encodeTags(tags),
      "description": description,
      "license": license,
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
