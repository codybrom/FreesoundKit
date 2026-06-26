//
//  FreesoundUsageMonitor.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/26/26.
//

#if canImport(Observation)

  import Foundation
  import Observation

  /// An opt-in, `@Observable` view over a ``FreesoundUsageTracker`` for SwiftUI.
  ///
  /// The tracker itself stays `Sendable` and lock-based so a ``FreesoundClient``
  /// can record into it from background request threads. This companion is the
  /// main-actor, observable surface: drop it in the environment and SwiftUI views
  /// re-render as ``snapshot`` changes.
  ///
  /// ```swift
  /// @State private var usage = FreesoundUsageMonitor(client.usageTracker)
  /// // ...
  /// .environment(usage)
  /// // in a view:
  /// Text("\(usage.snapshot.standard.remainingToday) reads left today")
  /// ```
  ///
  /// Freesound throttles on rolling windows that decay with wall-clock time, so
  /// the monitor re-snapshots on a timer (every `refresh`) even when no new
  /// requests are made. The timer stops automatically once the monitor is
  /// released; call ``stop()`` to end it sooner.
  @MainActor
  @Observable
  public final class FreesoundUsageMonitor {
    /// The most recent usage snapshot. Observed by SwiftUI.
    public private(set) var snapshot: FreesoundUsageTracker.Snapshot

    @ObservationIgnored private let tracker: FreesoundUsageTracker
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Creates a monitor that re-snapshots `tracker` every `refresh`.
    /// - Parameters:
    ///   - tracker: The tracker to observe. Held strongly.
    ///   - refresh: How often to re-read the tracker. Defaults to 5 seconds.
    public init(_ tracker: FreesoundUsageTracker, refresh: Duration = .seconds(5)) {
      self.tracker = tracker
      self.snapshot = tracker.snapshot()
      self.task = Self.makeTimer(tracker: tracker, refresh: refresh) { [weak self] next in
        // Observation notifies on every assignment, even an equal one, so an
        // idle meter would wake SwiftUI each tick for nothing. Only publish on
        // an actual change.
        guard let self, next != self.snapshot else { return }
        self.snapshot = next
      }
    }

    /// Re-reads the tracker immediately, e.g. right after issuing a request,
    /// rather than waiting for the next timer tick.
    public func refreshNow() {
      let next = tracker.snapshot()
      guard next != snapshot else { return }
      snapshot = next
    }

    /// Stops the refresh timer. The monitor also stops on its own when released.
    public func stop() {
      task?.cancel()
      task = nil
    }

    /// Builds the polling task. Captures only `Sendable` values plus a weak
    /// `update` callback, so the running task never keeps the monitor alive: once
    /// the monitor is released, the next tick's `update` is a no-op and the loop
    /// exits at the following cancellation check.
    private static func makeTimer(
      tracker: FreesoundUsageTracker,
      refresh: Duration,
      update: @escaping @MainActor (FreesoundUsageTracker.Snapshot) -> Void
    ) -> Task<Void, Never> {
      Task { @MainActor in
        while !Task.isCancelled {
          try? await Task.sleep(for: refresh)
          if Task.isCancelled { return }
          update(tracker.snapshot())
        }
      }
    }
  }

#endif
