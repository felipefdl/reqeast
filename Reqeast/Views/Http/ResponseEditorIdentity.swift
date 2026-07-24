//
//  ResponseEditorIdentity.swift
//  Reqeast
//

import Foundation

/// Builds the SwiftUI `.id` for read-only response editors.
///
/// The timestamp handles different responses that happen to share a length.
/// The text hash handles the same response re-rendered with a new jq filter,
/// where timestamp alone would not change and the editor would keep stale
/// content (CodeEditSourceEditor does not sync a re-bound `.constant` value
/// without view replacement).
enum ResponseEditorIdentity {
  static func id(timestamp: Date, text: String) -> String {
    "\(timestamp.timeIntervalSince1970)-\(text.hashValue)"
  }
}
