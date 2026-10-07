import Foundation

/// How the session list groups its rows. A device-local UI preference (persisted in
/// `PreferencesClient`), independent of the fetch order — all modes render the same
/// recency-sorted `sessions` array, just differently:
/// - `.workspace` groups rows by `cwd` (desktop-style), with the Pinned section on top.
/// - `.chronological` shows one flat, last-active-ordered list (no workspace headers).
/// - `.desktopSections` mirrors the desktop sidebar: pinned rows, date buckets for local
///   sessions, then source/endpoint buckets.
public enum SessionGroupingMode: String, Sendable, CaseIterable, Equatable {
  case workspace
  case chronological
  case desktopSections

  /// Date buckets used by the desktop-style session sidebar.
  public enum DesktopDateBucket: String, Sendable, Equatable, CaseIterable {
    case today
    case yesterday
    case earlierThisWeek
    case lastWeek
    case month
  }

  /// Default when nothing is persisted yet.
  public static let `default`: SessionGroupingMode = .workspace
}

/// A section in the desktop-style session layout. Date sections contain local sessions;
/// source sections contain sessions from a connected messaging endpoint.
public struct DesktopSessionSection: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Sendable {
    case date(SessionGroupingMode.DesktopDateBucket, month: Int?, year: Int?)
    case source(String)
  }

  public let kind: Kind
  public let title: String
  public var sessions: [Session]

  /// Rows for this section with branch nesting preserved within the section.
  public var entries: [SessionBranchEntry] {
    flattenSessionsWithBranches(sessions)
  }

  public var id: String {
    switch kind {
    case let .date(bucket, month, year):
      let monthValue = month.map(String.init) ?? ""
      let yearValue = year.map(String.init) ?? ""
      return "date-\(bucket.rawValue)-\(monthValue)-\(yearValue)"
    case let .source(source):
      return "source-\(source)"
    }
  }

  public init(kind: Kind, title: String, sessions: [Session]) {
    self.kind = kind
    self.title = title
    self.sessions = sessions
  }
}

extension SessionGroupingMode.DesktopDateBucket {
  var defaultTitle: String {
    switch self {
    case .today: return "Today"
    case .yesterday: return "Yesterday"
    case .earlierThisWeek: return "Earlier this week"
    case .lastWeek: return "Last week"
    case .month: return ""
    }
  }
}
