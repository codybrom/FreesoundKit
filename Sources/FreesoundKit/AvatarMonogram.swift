//
//  AvatarMonogram.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/26/26.
//

import Foundation

/// A deterministic, network-free stand-in for a user's avatar, mirroring
/// Freesound's own default-avatar rendering: the username's first letter over a
/// background color picked from a fixed 10-color palette.
///
/// This reproduces the server's logic (`bw_user_avatar` in
/// `general/templatetags/bw_templatetags.py`, with `AVATAR_BG_COLORS` from
/// `settings.py`), so the letter and color match freesound.org for the same
/// username. Use it as the fallback when ``User/avatar`` / ``Me/avatar`` has no
/// URL — or as a placeholder while ``FreesoundAssetCache`` loads the real image.
///
/// ```swift
/// let monogram = user.monogram
/// // SwiftUI: Circle().fill(Color(monogram.backgroundColor)).overlay(Text(monogram.letter))
/// ```
public struct AvatarMonogram: Sendable, Equatable, Hashable {
  /// The username this monogram represents.
  public let username: String
  /// The uppercased first character of ``username``, or `"?"` if it is empty.
  public let letter: String
  /// The background color from ``palette``, or `nil` if ``username`` is empty.
  public let backgroundColor: RGBColor?

  /// Builds the monogram for `username`, matching Freesound's selection: the
  /// palette index is the sum of the first two characters' Unicode code points
  /// modulo the palette size (just the first character for single-character
  /// names).
  public init(username: String) {
    self.username = username
    self.letter = username.first.map { String($0).uppercased() } ?? "?"

    let scalars = username.unicodeScalars
    guard let first = scalars.first else {
      self.backgroundColor = nil
      return
    }
    let count = UInt32(Self.palette.count)
    let index: Int =
      scalars.count >= 2
      ? Int((first.value + scalars[scalars.index(after: scalars.startIndex)].value) % count)
      : Int(first.value % count)
    self.backgroundColor = Self.palette[index]
  }

  /// Freesound's `AVATAR_BG_COLORS` — the 10-color default-avatar palette,
  /// `interpolate_colors(BeastWhoosh wave_colors[1:], num_colors=10)`
  /// precomputed with the server's integer truncation so values match the site.
  public static let palette: [RGBColor] = [
    RGBColor(red: 29, green: 159, blue: 181),
    RGBColor(red: 19, green: 179, blue: 147),
    RGBColor(red: 9, green: 199, blue: 113),
    RGBColor(red: 0, green: 220, blue: 80),
    RGBColor(red: 84, green: 213, blue: 72),
    RGBColor(red: 170, green: 206, blue: 65),
    RGBColor(red: 255, green: 200, blue: 58),
    RGBColor(red: 255, green: 133, blue: 62),
    RGBColor(red: 255, green: 66, blue: 66),
    RGBColor(red: 255, green: 0, blue: 70),
  ]
}

/// An 8-bit-per-channel RGB color. Used by ``AvatarMonogram`` to express
/// Freesound's avatar palette without depending on a UI framework; map it to
/// your platform's color type at the call site.
public struct RGBColor: Sendable, Equatable, Hashable, Codable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// The channels as `0...1` fractions, e.g. for `SwiftUI.Color(red:green:blue:)`.
  public var fractions: (red: Double, green: Double, blue: Double) {
    (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
  }
}

extension User {
  /// A default-avatar monogram for this user, matching freesound.org. Use as a
  /// fallback when ``avatar`` has no URL for the size you want.
  public var monogram: AvatarMonogram { AvatarMonogram(username: username) }
}

extension Me {
  /// A default-avatar monogram for the authenticated user, matching freesound.org.
  public var monogram: AvatarMonogram { AvatarMonogram(username: username) }
}
