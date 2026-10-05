import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

/// Cron Jobs section: grouping, capability gating, unread badge, and the inline peek.
@MainActor
struct SessionListCronTests {
  private let connection = ServerConnection(baseURL: URL(string: "http://mac.tailnet:9119")!, token: "tok")
  private let now = Date(timeIntervalSince1970: 1_749_600_000)

  private func cronSession(
    _ jobID: String, stamp: String, messageCount: Int = 1, updatedAt: TimeInterval = 0
  ) -> Session {
    Session(
      id: "cron_\(jobID)_\(stamp)",
      updatedAt: Date(timeIntervalSince1970: updatedAt),
      messageCount: messageCount,
      source: "cron"
    )
  }

  // MARK: Grouping (pure state)

  @Test func groupsRunsUnderTheirJobsByEmbeddedID() {
    let state = SessionListFeature.State(
      connection: connection,
      sessions: [
        cronSession("job1", stamp: "20260701_090000", updatedAt: 100),
        cronSession("job1", stamp: "20260702_090000", updatedAt: 200),
        cronSession("job2", stamp: "20260702_100000", updatedAt: 300),
        Session(id: "interactive", title: "Chat"),
      ],
      cronJobs: [CronJob(id: "job1", name: "Digest"), CronJob(id: "job2", name: "Backup")]
    )

    let groups = state.cronJobGroups
    // Neither job has a next run → alphabetical by title: Backup (job2), Digest (job1).
    #expect(groups.map(\.id) == ["job2", "job1"])
    let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
    // Runs are newest-first within a job (inherits cronSessions' recency sort).
    #expect(byID["job1"]?.runs.map(\.id) == [
      "cron_job1_20260702_090000", "cron_job1_20260701_090000",
    ])
    #expect(byID["job2"]?.runs.count == 1)
    // Interactive sessions never leak into cron groups.
    #expect(groups.flatMap(\.runs).allSatisfy { $0.isCron })
  }

  @Test func jobsSortSoonestNextRunFirstThenNilThenTitle() {
    let state = SessionListFeature.State(
      connection: connection,
      cronJobs: [
        CronJob(id: "j-none-b", name: "Zeta"),
        CronJob(id: "j-late", name: "Late", nextRunAt: now.addingTimeInterval(7200)),
        CronJob(id: "j-none-a", name: "Alpha"),
        CronJob(id: "j-soon", name: "Soon", nextRunAt: now.addingTimeInterval(60)),
      ]
    )

    #expect(state.cronJobGroups.map(\.id) == ["j-soon", "j-late", "j-none-a", "j-none-b"])
  }

  @Test func peekCapsRunsButUnreadJudgesAllRuns() {
    // 7 runs, newest 5 peeked; ONLY the oldest (6th/7th, outside the peek) is unread —
    // the job dot must still light up.
    var sessions: [Session] = []
    for day in 1...7 {
      sessions.append(cronSession(
        "job1", stamp: "2026070\(day)_090000", messageCount: 3, updatedAt: TimeInterval(day * 100)
      ))
    }
    var seen = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, 3) })
    seen["cron_job1_20260701_090000"] = 1  // the OLDEST run has unseen output
    let state = SessionListFeature.State(
      connection: connection,
      sessions: IdentifiedArray(uniqueElements: sessions),
      seenCounts: seen,
      cronJobs: [CronJob(id: "job1", name: "Digest")]
    )

    let group = state.cronJobGroups[0]
    #expect(group.runs.count == SessionListFeature.State.cronPeekLimit)
    // Newest-first: the peek holds days 7...3; the unread day-1 run is outside it.
    #expect(!group.runs.map(\.id).contains("cron_job1_20260701_090000"))
    #expect(group.hasUnread)
    #expect(state.cronUnreadCount == 1)
  }

  @Test func runsMatchingNoJobLandInUnmatchedBucket() {
    let state = SessionListFeature.State(
      connection: connection,
      sessions: [
        cronSession("job1", stamp: "20260702_090000"),
        cronSession("deleted-job", stamp: "20260702_100000"),
        Session(id: "cron_odd-shape", source: "cron"),  // unparseable id (no datetime tail)
      ],
      cronJobs: [CronJob(id: "job1")]
    )

    #expect(state.unmatchedCronSessions.map(\.id) == [
      "cron_deleted-job_20260702_100000", "cron_odd-shape",
    ])
    #expect(state.cronJobGroups.flatMap(\.runs).map(\.id) == ["cron_job1_20260702_090000"])
  }

  @Test func groupingInactiveWhenUnsupportedOrNoJobs() {
    let unsupported = SessionListFeature.State(
      connection: connection,
      sessions: [cronSession("job1", stamp: "20260702_090000")],
      cronJobs: [CronJob(id: "job1")],
      cronJobsSupported: false
    )
    #expect(unsupported.cronJobGroups.isEmpty)
    #expect(unsupported.unmatchedCronSessions.isEmpty)  // flat fallback shows everything

    let noJobs = SessionListFeature.State(
      connection: connection,
      sessions: [cronSession("job1", stamp: "20260702_090000")]
    )
    #expect(noJobs.cronJobGroups.isEmpty)
    #expect(noJobs.unmatchedCronSessions.isEmpty)
  }

  @Test func cronUnreadCountCountsOnlyUnreadCronSessions() {
    let state = SessionListFeature.State(
      connection: connection,
      sessions: [
        cronSession("job1", stamp: "20260701_090000", messageCount: 5),  // unread (seen 2)
        cronSession("job1", stamp: "20260702_090000", messageCount: 3),  // read (seen 3)
        Session(id: "interactive", messageCount: 9),  // unread but NOT cron
      ],
      seenCounts: [
        "cron_job1_20260701_090000": 2,
        "cron_job1_20260702_090000": 3,
        "interactive": 1,
      ]
    )

    #expect(state.cronUnreadCount == 1)
    #expect(state.unreadSessionIDs.contains("interactive"))  // interactive dot unaffected
  }

  // MARK: Fetch + capability gate (store)

  @Test func refreshFetchesCronJobsScopedToSelectedProfile() async {
    let requestedProfile = LockIsolated<String?>("unset")
    // Hoisted: the @Sendable dependency closure can't call the MainActor-isolated helper.
    let run = cronSession("job1", stamp: "20260702_090000")
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection, selectedProfileName: "work", profilesSupported: true
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesProfiles.sessions = { @Sendable _, _, _, _, _, _ in [run] }
      $0.hermesREST.cronJobs = { @Sendable _, profile in
        requestedProfile.setValue(profile)
        return [CronJob(id: "job1", name: "Digest")]
      }
    }

    await store.send(.pulledToRefresh) {
      $0.now = self.now
      $0.isLoading = true
      $0.sessionFetchGeneration += 1
    }
    await store.receive {
      guard case let .profileSessionsResponse("work", "", 1, .success(sessions)) = $0 else { return false }
      return sessions == [run]
    } assert: {
      $0.isLoading = false
      $0.sessionsProfileName = "work"
      $0.sessions = [self.cronSession("job1", stamp: "20260702_090000")]
      $0.seenCounts = ["cron_job1_20260702_090000": 1]  // cron sessions ARE seeded (issue #24 gap 1)
    }
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = [CronJob(id: "job1", name: "Digest")]
    }
    // Profile-scoped agents get the LITERAL selected name (matching the scoped session list).
    #expect(requestedProfile.value == "work")
  }

  @Test func notFoundDisablesCronJobsAndSkipsLaterFetches() async {
    let fetchCount = LockIsolated(0)
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesREST.sessions = { @Sendable _, _, _, _ in [] }
      $0.hermesREST.cronJobs = { @Sendable _, _ in
        fetchCount.withValue { $0 += 1 }
        throw RESTError.notFound
      }
    }

    await store.send(.pulledToRefresh) {
      $0.now = self.now
      $0.isLoading = true
      $0.sessionFetchGeneration += 1
    }
    await store.receive {
      guard case let .unscopedSessionsResponse("default", "", 1, false, .success(sessions)) = $0 else { return false }
      return sessions.isEmpty
    } assert: {
      $0.isLoading = false
    }
    await store.receive(\.cronJobsResponse.failure) {
      $0.cronJobsSupported = false
    }

    // The flag is definitive: the next refresh fetches sessions only.
    await store.send(.pulledToRefresh) {
      $0.isLoading = true
      $0.sessionFetchGeneration += 1
    }
    await store.receive {
      guard case let .unscopedSessionsResponse("default", "", 2, false, .success(sessions)) = $0 else { return false }
      return sessions.isEmpty
    } assert: {
      $0.isLoading = false
    }
    #expect(fetchCount.value == 1)
  }

  @Test func transientFailureKeepsPreviousJobs() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [CronJob(id: "job1", name: "Digest")]
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesREST.sessions = { @Sendable _, _, _, _ in [] }
      $0.hermesREST.cronJobs = { @Sendable _, _ in throw RESTError.unreachable }
    }

    await store.send(.pulledToRefresh) {
      $0.now = self.now
      $0.isLoading = true
      $0.sessionFetchGeneration += 1
    }
    await store.receive {
      guard case let .unscopedSessionsResponse("default", "", 1, false, .success(sessions)) = $0 else { return false }
      return sessions.isEmpty
    } assert: {
      $0.isLoading = false
    }
    // No state change: previous jobs survive a transient failure (no section flapping).
    await store.receive(\.cronJobsResponse.failure)
    #expect(store.state.cronJobs == [CronJob(id: "job1", name: "Digest")])
    #expect(store.state.cronJobsSupported)
  }

  @Test func unscopedAgentFetchesCronJobsWithNilProfile() async {
    let requestedProfile = LockIsolated<String?>("unset")
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesREST.sessions = { @Sendable _, _, _, _ in [] }
      $0.hermesREST.cronJobs = { @Sendable _, profile in
        requestedProfile.setValue(profile)
        return []
      }
    }

    await store.send(.pulledToRefresh) {
      $0.now = self.now
      $0.isLoading = true
      $0.sessionFetchGeneration += 1
    }
    await store.receive {
      guard case let .unscopedSessionsResponse("default", "", 1, false, .success(sessions)) = $0 else { return false }
      return sessions.isEmpty
    } assert: {
      $0.isLoading = false
    }
    await store.receive(\.cronJobsResponse.success)
    #expect(requestedProfile.value == nil)
  }

  // MARK: Inline peek + unread-on-open

  @Test func cronJobTappedTogglesSingleOpenPeek() async {
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    }

    await store.send(.cronJobTapped(id: "job1")) {
      $0.expandedCronJobID = "job1"
    }
    // Expanding another job collapses the first (single-open).
    await store.send(.cronJobTapped(id: "job2")) {
      $0.expandedCronJobID = "job2"
    }
    // Tapping the open job collapses it.
    await store.send(.cronJobTapped(id: "job2")) {
      $0.expandedCronJobID = nil
    }
  }

  // MARK: Manage actions (trigger / pause / resume)

  @Test func triggerSuccessRefetchesSessionsAndJobs() async {
    let triggered = LockIsolated<String?>(nil)
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesREST.triggerCronJob = { @Sendable _, id, _ in triggered.setValue(id) }
      $0.hermesREST.sessions = { @Sendable _, _, _, _ in [] }
      $0.hermesREST.cronJobs = { @Sendable _, _ in [CronJob(id: "job1", state: "running")] }
    }

    await store.send(.triggerCronJob(id: "job1")) {
      $0.cronActionInFlightIDs = ["job1"]
    }
    await store.receive(\.cronJobActionFinished) {
      $0.cronActionInFlightIDs = []
      $0.now = self.now
      $0.isLoading = true  // trigger → FULL load so the new run session appears
      $0.sessionFetchGeneration = 1
    }
    await store.receive {
      guard case let .unscopedSessionsResponse("default", "", 1, false, .success(sessions)) = $0 else { return false }
      return sessions.isEmpty
    } assert: {
      $0.isLoading = false
    }
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = [CronJob(id: "job1", state: "running")]
    }
    #expect(triggered.value == "job1")
  }

  @Test func pauseSuccessRefetchesJobsOnly() async {
    // `hermesREST.sessions` is deliberately NOT stubbed: if pause triggered a session
    // fetch, the unimplemented dependency would fail this test.
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [CronJob(id: "job1", state: "scheduled")]
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.pauseCronJob = { @Sendable _, _, _ in }
      $0.hermesREST.cronJobs = { @Sendable _, _ in [CronJob(id: "job1", state: "paused")] }
    }

    await store.send(.pauseCronJob(id: "job1")) {
      $0.cronActionInFlightIDs = ["job1"]
    }
    await store.receive(\.cronJobActionFinished) {
      $0.cronActionInFlightIDs = []
    }
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = [CronJob(id: "job1", state: "paused")]  // server-reconciled, not optimistic
    }
  }

  @Test func resumeSuccessRefetchesJobsOnly() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [CronJob(id: "job1", state: "paused")]
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.resumeCronJob = { @Sendable _, _, _ in }
      $0.hermesREST.cronJobs = { @Sendable _, _ in [CronJob(id: "job1", state: "scheduled")] }
    }

    await store.send(.resumeCronJob(id: "job1")) {
      $0.cronActionInFlightIDs = ["job1"]
    }
    await store.receive(\.cronJobActionFinished) {
      $0.cronActionInFlightIDs = []
    }
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = [CronJob(id: "job1", state: "scheduled")]
    }
  }

  @Test func actionFailureSurfacesBannerAndKeepsState() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [CronJob(id: "job1", state: "scheduled")]
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.triggerCronJob = { @Sendable _, _, _ in
        throw RESTError.server(status: 400, detail: "job is paused")
      }
    }

    await store.send(.triggerCronJob(id: "job1")) {
      $0.cronActionInFlightIDs = ["job1"]
    }
    await store.receive(\.cronJobActionFinished) {
      $0.cronActionInFlightIDs = []
      $0.loadError = RESTError.server(status: 400, detail: "job is paused").message
    }
    // No refetch on failure — jobs stay as they were.
    #expect(store.state.cronJobs == [CronJob(id: "job1", state: "scheduled")])
  }

  @Test func actionIsIgnoredWhileAlreadyInFlight() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronActionInFlightIDs: ["job1"]
      )
    ) {
      SessionListFeature()
    }
    // No RPC stub: firing the request would fail on the unimplemented dependency.
    await store.send(.triggerCronJob(id: "job1"))
    await store.send(.pauseCronJob(id: "job1"))
    await store.send(.resumeCronJob(id: "job1"))
  }

  @Test func openingACronRunMarksItSeen() async {
    let run = cronSession("job1", stamp: "20260702_090000", messageCount: 5)
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        sessions: [run],
        seenCounts: [run.id: 2]  // unread: 5 > 2
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.preferences = .inMemory()
    }

    #expect(store.state.cronUnreadCount == 1)
    await store.send(.sessionTapped(run.id)) {
      $0.seenCounts[run.id] = 5
    }
    await store.receive(\.delegate.openSession)
    #expect(store.state.cronUnreadCount == 0)
  }
}
