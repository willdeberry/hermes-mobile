# Session pin sync follow-ups — PR #113

PR: https://github.com/goncharik/hermes-mobile/pull/113

Status: **Follow-up implementation and review complete; no commit/push made.**

This is a TODO list based on the consolidated review feedback on PR #113. Do not begin implementation until the user explicitly starts the next item. Re-check the exact review wording and current source when each item is started; reviewer claims below are recorded as work items, not independently re-verified conclusions.

## Ordered TODO

- [x] **1. Protect existing local pins during first server reconciliation.**
      Implemented a durable, per-server-URL legacy-pin snapshot before importing server pins.
      Explicit profile rows upload pending local pins; false cannot remove them until upload
      succeeds. Missing/nil rows stay pending, partial failures retry, and successful IDs are
      checkpointed individually. Existing ordering and server-only pins survive. Migration
      attempt IDs, identity checkpoints, and fetch invalidation reject stale completions;
      completion never restores old pin/row snapshots. Token changes do not restart migration.
      Verified on the approved shared Mac checkout via SSH, external scratch path
      `$HOME/Library/Caches/hermes-mobile-swift-build`, filter
      `(SessionListFeatureTests|PreferencesClientTests)/pinMigration`: **10 tests passed**
      in 2 suites, zero failures. RED first reproduced erased local pins and missing uploads;
      additional RED/GREEN cases covered stale user-write completion, optimistic-unpin retry,
      and identity-checkpoint mismatch. Final source/test hashes matched locally/remotely
      before and after the run. Original dirty `Package.resolved` restored byte-for-byte.
      Only focused migration tests ran; no commit/push. Items 2–9 remain untouched.

- [x] **2. Preserve local-only pinning when profile support is unavailable.**
      Shared row eligibility now permits device-local Pin/Unpin when `profilesSupported`
      is false, including legacy search rows. Trusted-profile server eligibility remains
      separate; modern search/unscoped/wrong-profile rows still cannot fall back locally.
      Local changes preserve insertion order, persist synchronously, and stop before REST
      writes, server mutation bookkeeping, or fetch-generation invalidation. Missing-row,
      archive/delete, and pending-mutation guards remain. The view already uses the same
      `canChangePin` policy and needed no production edit.

      Strict TDD: before production edits, `legacyPinChangesStayLocal(search:pinned:)`
      failed in all 4 search/non-search × Pin/Unpin cases (16 expected issues: eligibility,
      state/error, persistence, and no-error assertions). The 6 legacy row-guard cases
      passed on RED. GREEN ran only these exact `SessionListFeatureTests` names:
      - `legacyPinChangesStayLocal` — 4 cases, live preferences reopened to verify persistence.
      - `legacyPinChangesKeepRowGuards` — 6 cases.
      - `pinWritesRequireTrustedCurrentProfileRows` — 12 modern-server cases; the obsolete
        unsupported-server rejection cases were replaced by the local-behavior matrix.
      - `pinAffordanceUsesReducerEligibility` — shared view/reducer policy wiring.
      - `pinAndUnpinWriteProfileScopedServerMembership` — existing modern writes.
      - `pinWriteUsesExplicitDefaultProfile` — existing explicit default-profile write.

      Approved shared Mac checkout, no copying:
      `ssh will@192.168.1.195 'cd ~/code/remote/hermes-mobile/HermesKit && swift test --scratch-path "$HOME/Library/Caches/hermes-mobile-swift-build" --filter "SessionListFeatureTests/(legacyPinChangesStayLocal|legacyPinChangesKeepRowGuards|pinWritesRequireTrustedCurrentProfileRows|pinAffordanceUsesReducerEligibility|pinAndUnpinWriteProfileScopedServerMembership|pinWriteUsesExplicitDefaultProfile)"'`
      Result: **6 tests in 1 suite passed, 25 executed cases, zero failures**.
      No broad suite or standalone build. `git diff --check` passed.
      Nonblocking compiler warnings concerned existing non-Sendable `AppFeature.Action`
      captures in `AppFeatureTests.swift`; no TODO #2 warning or blocker.
      Logs: `/home/will/.hermes/cache/scratch/todo2-red.log` and `todo2-green.log`.

      SHA-256 matched locally/remotely before and after GREEN:
      - `HermesKit/Sources/HermesKit/Features/SessionListFeature.swift`:
        `db72a1d5f8393ccea66682ca9d2f2ebe874974733500801f63e4acb36b6da2d9`
      - `HermesKit/Tests/HermesKitTests/SessionListFeatureTests.swift`:
        `beb1b48f7c0fe44537ab5ba828f014314e8d696ca587d9b755dd0880f08cfa8c`
      - Unchanged `HermesMobile/Sources/Features/SessionListView.swift`:
        `ef749f7af291ec49fc7ab1945f8fa56c5b8577e5e623fcae3d769a12c01c4626`
      Original dirty `HermesKit/Package.resolved` bytes captured before testing at
      `/home/will/.hermes/cache/scratch/todo2-package-resolved.before` (4356 bytes);
      before/after SHA-256 `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`.
      No resolver churn occurred; byte comparison confirmed the original remained intact.
      TODO #1 migration and unrelated dirty files preserved; items 3–9 untouched.
      No commit/push.

- [x] **3. Add a capability fallback when `pinned` is absent.**
      Trusted current-profile rows with `pinned == nil` retain device-local membership and
      Pin/Unpin persist locally without PATCH, mutation bookkeeping, or fetch invalidation.
      Capability is per row, like the existing unread-field fallback: explicit true/false rows
      still write to the server even beside nil rows. No global capability downgrade is cached.
      Existing provenance/search/removal/pending-write guards and TODO #2 legacy behavior stay
      intact. TODO #1 already excludes nil rows from migration PATCH and preserves nil membership;
      its existing single-capability and mixed-row tests passed without production migration edits.

      Strict TDD: `absentPinCapabilityChangesStayLocal` failed before production edits in all
      4 Pin/Unpin × nil-only/mixed cases, with 28 expected issues (unexpected PATCH/completion,
      mutation bookkeeping, and fetch generation). A target-row capability guard made all 4 pass.
      Added explicit true/false × single/mixed regression coverage (4 cases); corrected five
      existing server-write test fixtures to advertise explicit pin capability, retaining assertions.

      Only these exact `SessionListFeatureTests` names ran in final GREEN:
      - `absentPinCapabilityChangesStayLocal` — 4 cases.
      - `explicitPinCapabilityWritesInMixedRows` — 4 cases.
      - `legacyPinChangesStayLocal` — 4 cases.
      - `legacyPinChangesKeepRowGuards` — 6 cases.
      - `pinWritesRequireTrustedCurrentProfileRows` — 12 cases.
      - `pinAffordanceUsesReducerEligibility`.
      - `pinAndUnpinWriteProfileScopedServerMembership`.
      - `pinWriteUsesExplicitDefaultProfile`.
      - `pinMigrationUploadsLocalPinsBeforeAcceptingServerFalse`.
      - `pinMigrationRequiresCurrentExplicitProfileRows` — 4 cases.
      - `pinMigrationCompletedReconcilesExplicitPinsPreservingLocalOrderAndAbsentIDs`.
      - `pinMigrationCompletedUsesFirstDuplicateAndPersistsWithoutNewSeenCounts` — 2 cases.
      - `pinMovesSessionIntoPinnedSetAndOutOfGroup`.
      - `unpinRestoresSessionToGroup`.
      - `pinnedSessionsFollowPinInsertionOrder`.
      - `pinWriteProtectsPendingAndCompletedMembership` — 4 cases.
      - `pendingPinWriteRejectsRemovalUntilCompletion` — 4 cases.
      - `pendingPinWriteRejectsArchivedSheetDelete` — 4 cases.
      - `concurrentUnpinsAreIgnoredUntilPendingWriteFinishes`.
      - `pinCompletionRestartsInFlightListAndRejectsItsLateResponse`.
      - `pinFailureAfterProfileRoundTripPreservesNewerSameIDMembership`.

      Approved shared Mac checkout `will@192.168.1.195:~/code/remote/hermes-mobile`,
      no copying; `swift test` from `HermesKit` with external scratch path
      `$HOME/Library/Caches/hermes-mobile-swift-build` and the exact-name filter above.
      Result: **21 tests in 1 suite, 59 executed cases, zero failures**.
      No compiler warnings in these runs; only the nonblocking SSH known-host notice.
      `git diff --check` passed. Logs under `/home/will/.hermes/cache/scratch/`:
      `todo3-red.log`, `todo3-green-initial.log`, `todo3-green.log`.

      Source/test SHA-256 matched locally/remotely before and after final GREEN:
      - `HermesKit/Sources/HermesKit/Features/SessionListFeature.swift`:
        `2e1e948c5ec8d72fc05d81683c8946b2b62ebec827bca98953423c9027104ce0`.
      - `HermesKit/Tests/HermesKitTests/SessionListFeatureTests.swift`:
        `a6b225b0db03b7cea32e434179d1d0d83ddd84da7dd518335ad3819c439c3e63`.
      Original dirty `HermesKit/Package.resolved` remained byte-for-byte unchanged versus
      `/home/will/.hermes/cache/scratch/todo3-package-resolved.before`; SHA-256 before/after:
      `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`.
      Only this checklist item was updated. No broad suite, commit, or push; TODOs 4–9 untouched.

- [ ] **4. Restore safe pinning from search.**
      **Reviewed; modern search restoration blocked on trustworthy ownership.** The reviewer’s
      selected-profile + session-ID claim is not compatible with the current client contract:
      `HermesRESTClient.search` sends only `q` to `/api/sessions/search` (lines 372–375), while
      `setPinned` sends the selected profile in both query and body (397–403). `SearchResultDTO`
      retains only session ID, snippet, and start time (901–918): no profile provenance and no
      pin capability. `Session.source` denotes origin (cli/cron/etc.), not profile ownership.
      Capturing the selected profile in an unscoped response guards request freshness; it does
      not prove the returned session belongs to that profile. Explicit `pinned` alone would
      establish capability, not ownership; nil does not authorize an untrusted local fallback.

      Corroborating local agent source (not a claim about every deployed server):
      `/home/will/.hermes/hermes-agent/hermes_cli/web_routers/sessions.py` opens search's DB
      with its optional request profile (285–298, 461); absent profile identifies the serving
      process's profile (147–150), not the mobile selection. PATCH opens the DB selected by
      `body.profile` (892–922). Selecting `work` on mobile therefore need not target the DB
      searched without a profile. A same-ID row in another profile cannot prove ownership.

      Minimal safe rule remains: unsupported profiles permit local-only changes; modern
      server writes require trusted selected-profile row provenance AND explicit target-row
      capability. Trusted nil rows remain local-only. Search would need a verified scoped
      request/response contract or decoded authoritative ownership before relaxing this rule.
      Do not infer ownership from the selection, ID, cached pin membership, or source string.
      No production changes were made and no guards were weakened. Legacy search Pin/Unpin
      is already restored by TODO #2. This item stays unchecked rather than forcing modern
      behavior. No feature RED/GREEN is claimed: existing safe behavior passed regression
      tests; manufacturing a failure would not justify unsafe implementation.

      Added `searchPinChangesRequireOwnershipNotCapability` — 12 exhaustive cases across
      legacy/modern × absent/false/true capability × Pin/Unpin. Accepted current search
      responses discard prior list provenance; modern rows do not mutate local preferences
      or PATCH, while legacy rows persist locally regardless of advertised pin capability.
      Neither branch starts migration, creates mutations, nor invalidates fetch generations.

      Only these exact `SessionListFeatureTests` names ran:
      - `searchPinChangesRequireOwnershipNotCapability` — 12 cases.
      - `legacyPinChangesStayLocal` — 4 cases.
      - `legacyPinChangesKeepRowGuards` — 6 cases.
      - `absentPinCapabilityChangesStayLocal` — 4 cases.
      - `pinWritesRequireTrustedCurrentProfileRows` — 12 cases.
      - `pinAffordanceUsesReducerEligibility`.
      - `unscopedListAndSearchNeverReconcilePins` — 2 cases.
      - `staleProfileListSuccessAndFailureAreIgnored` — 5 cases.
      - `newerProfileFetchAndSearchInvalidateOldGenerations`.
      - `profileRoundTripAndSearchClearRejectEarlierResponses`.
      - `pinMigrationRequiresCurrentExplicitProfileRows` — 4 cases.
      - `searchIsDebouncedAndHitsSearchEndpoint`.

      Approved shared Mac checkout, no file copying; SwiftPM external scratch path
      `$HOME/Library/Caches/hermes-mobile-swift-build`. Result: **12 tests in 1 suite,
      53 executed cases, zero failures**. Initial end-anchored name filter matched no tests;
      corrected filter reran all names above. No compiler warnings on the successful run;
      only SSH known-host notice. Log: `/home/will/.hermes/cache/scratch/todo4-tests.log`.
      `git diff --check` passed. Source/test/view SHA-256 matched locally/remotely before
      and after the successful run:
      - Reducer (unchanged): `2e1e948c5ec8d72fc05d81683c8946b2b62ebec827bca98953423c9027104ce0`.
      - Tests: `73fe4d0f63792654eab634985ea483cb7f1f31f3116f6d3c422d9220e419b5e5`.
      - View (unchanged): `ef749f7af291ec49fc7ab1945f8fa56c5b8577e5e623fcae3d769a12c01c4626`.
      Original dirty `Package.resolved` remained byte-for-byte identical to
      `/home/will/.hermes/cache/scratch/todo4-package-resolved.before`; before/after SHA-256:
      `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`.
      TODOs #1–3 and unrelated dirty files preserved. No broad suite, commit, or push.

- [x] **5. Resolve pending-write interaction and refresh behavior.**
      Same-ID archive/delete confirmations and archived-sheet deletes now use the existing
      `loadError` banner: “Wait for the pin change to finish, then try again.” No optimistic
      removal, persistence change, destructive RPC, or delegate occurs while blocked.
      Pin/Unpin eligibility now guards only the target ID, leaving unrelated rows actionable.
      Overlapping unpins retain ordering anchors so failure rollback restores only the failed
      ID without reordering existing pins or undoing another row’s successful edit.
      A refresh canceled at pin initiation retains its loading intent; completion (success or
      failure) restarts the current context. Existing search restart and stale-response guards
      remain intact. No view changes, search API changes, profile rename work, or simplification.

      Strict TDD, approved shared Mac checkout only, no file copying, external SwiftPM scratch
      `$HOME/Library/Caches/hermes-mobile-swift-build`:
      - Feedback RED: 8 cases failed only on missing banner; GREEN: all 8 passed.
      - Unrelated-row RED: eligibility/write/persistence assertions failed; GREEN passed.
      - Refresh RED: pre-pin refresh cases failed to restart on success/failure; all 4 GREEN.
      - Concurrent rollback RED: 2 of 4 ordering cases failed; all 4 GREEN after ordering anchors.
      - Search restart already worked: 2 new success/failure regression cases passed without
        search production changes (not claimed as a new RED).

      Final focused GREEN: **24 tests in 1 suite, 66 executed cases, zero failures**.
      Exact `SessionListFeatureTests` names (only these ran):
      - `pendingPinWriteRejectsRemovalUntilCompletion` — 4 cases.
      - `pendingPinWriteRejectsArchivedSheetDelete` — 4 cases.
      - `unrelatedUnpinRemainsActionableWhilePinWriteIsPending` — 1 case.
      - `concurrentUnpinFailuresPreserveOrder` — 4 cases.
      - `pinCompletionRestartsInFlightListAndRejectsItsLateResponse` — 4 cases.
      - `pinCompletionRestartsCurrentSearchAndRejectsStaleResponses` — 2 cases.
      - `pinWriteProtectsPendingAndCompletedMembership` — 4 cases.
      - `pinFailureAfterProfileRoundTripPreservesNewerSameIDMembership` — 1 case.
      - `pinAffordanceUsesReducerEligibility` — 1 case.
      - `legacyPinChangesStayLocal` — 4 cases.
      - `legacyPinChangesKeepRowGuards` — 6 cases.
      - `absentPinCapabilityChangesStayLocal` — 4 cases.
      - `searchPinChangesRequireOwnershipNotCapability` — 12 cases.
      - `pinMigrationUploadsLocalPinsBeforeAcceptingServerFalse` — 1 case.
      - `pinMigrationRequiresCurrentExplicitProfileRows` — 4 cases.
      - `confirmArchiveRemovesSessionOptimisticallyAndCallsRPC` — 1 case.
      - `archiveFailureRestoresPinAndSeenState` — 1 case.
      - `confirmDeleteRemovesSessionOptimisticallyAndCallsRPC` — 1 case.
      - `deleteFailureRestoresSessionPinAndSeenStateAndSetsError` — 1 case.
      - `deleteOnOlderAgentFlipsCapabilityOffSilently` — 2 cases.
      - `deleteSuccessRestartsAFetchStartedDuringTheWindow` — 1 case.
      - `deleteSuccessDuringSearchRefreshesTheSearchResults` — 1 case.
      - `archiveSuccessAfterClearingSearchRestartsThePendingReload` — 1 case.
      - `archivedSheetDeleteRunsTheRoundTripAtTheListAndReinjectsSuccess` — 1 case.

      Source/test SHA-256 matched locally/remotely before and after final GREEN:
      - SessionListFeature.swift: `48eb2dabef73ca8ec3543aed9e22ce3a6ca318c596c8b95c294616651b75eb43`.
      - ArchivedSessionsFeature.swift: `10d9503c26ed7d90c68397583ccf7217b5109525868bfff0d6105a047682fc48`.
      - SessionListFeatureTests.swift: `93e0d3670b01f47998b115d890681aa4f2a5ce5c54db1bc5c8a8eefc9e572c28`.
      Original dirty `HermesKit/Package.resolved` preserved byte-for-byte; before/after SHA-256:
      `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`.
      `git diff --check` passed. Logs and exact filter/hash report are under
      `/home/will/.hermes/cache/scratch/todo5-*` (`todo5-final-green.log`, `todo5-verification.json`).
      Nonblocking: one intermediate test needed an explicit second completion receive; one
      intermediate compile needed a value capture for Swift concurrency. Both fixed. Existing
      AppFeatureTests non-Sendable capture warnings appeared during an intermediate rebuild;
      no compiler warnings in final GREEN. SSH known-host notice only. TODOs #1–4 and all
      unrelated dirty files preserved. Only this plan item updated; no commit/push.

- [x] **6. Simplify the mutation and fetch machinery without weakening correctness.**
      **Reviewed and intentionally left unchanged.** The current machinery was evaluated
      against TODOs #1–5; no safe simplification was justified without weakening correctness.
      No production or test changes were needed, and the item is complete as a documented
      no-op rather than an omitted review.

      Concrete candidates and retained requirements:
      - `pinWriteFinished` repeats `pinned`, `previousIndex`, and `query` already held in
        `PinMutation`. These are currently validated, not merely unused payload. Narrowing
        the action needs evidence that completion identity remains sufficient; do not replace
        it with a whole mutation snapshot (rollback permission/order can change in flight).
      - The first failure-banner assignment in `pinWriteFinished` appears redundant with
        the assignment after fetch restart. The latter must remain: `load` clears errors.
        This cosmetic candidate alone does not supply a behavioral RED for a code change.
      - Migration and user completion paths share restart code but have different semantics:
        migration acknowledges a durable server/identity checkpoint and must never roll back
        a membership snapshot. Its attempt UUID rejects reducer-recreation generation reuse.
      - `cancelOrRestartFetch` is not a drop-in replacement for pin completion's explicit
        invalidation: its loading branch delegates invalidation to `load`, which can return
        early for an optimistic profile rename. Do not change profile rename for this item.
      - Fetch generation rejects repeated same-context results; profile/query/capability
        guards and scoped-vs-unscoped actions establish different acceptance/ownership rules.
        Cancellation alone cannot replace them; selected profile is not search ownership.
      - Serialization is already per ID after TODO #5. Parent/archived-child pending-ID
        coordination blocks removal before optimistic edits; ordering anchors and
        `rollbackAllowed` preserve concurrent and cross-profile rollback. No redundant
        global pin lock remains to remove.

      Prepared a directly relevant exact-name selection: 25 `SessionListFeatureTests` plus
      `PreferencesClientTests/pinMigrationCheckpointsAreServerScopedAndIdentityResettable`,
      covering stale response/provenance, migration checkpoints, rollback/order, pending
      destructive actions, unrelated rows, refresh/search restart, and legacy/nil capability.
      Initial execution was blocked by the approved Mac being unreachable; no RED/GREEN was
      claimed and no production refactor was forced.

      The Mac became reachable and the exact selection then ran successfully with SwiftPM's
      external scratch path `$HOME/Library/Caches/hermes-mobile-swift-build`: **26 tests in 2
      suites, 0 failures**, exit code 0. The runner selected the intended parameterized cases
      (including migration, stale-response, rollback/order, pending-removal, refresh/search,
      legacy, nil-capability, mixed-capability, and search-ownership coverage). No production
      or test changes were justified: the candidate simplifications remain unproven and the
      current distinct guards retain separate correctness responsibilities.

      Selection: `/home/will/.hermes/cache/scratch/todo6-filter.txt`; final output:
      `/home/will/.hermes/cache/scratch/todo6-focused-run.log`. `git diff --check` passed;
      all tracked source/test hashes remained unchanged. Original dirty
      `HermesKit/Package.resolved` preserved byte-for-byte; SHA-256:
      `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`.
      TODOs #1–5 and unrelated work preserved. TODO #6 is complete as an intentional no-op;
      no commit/push.

- [x] **7. Separate unrelated profile-rename changes.**
      **Separation review complete; no safe worktree extraction, production unchanged.**
      Compared original pinning commit `9b9e1165eba3f7547ad10ebe9d0f5965ff9b103f`
      against its parent `bea4cc0`, then compared HEAD with the uncommitted follow-ups.
      The rename additions are already committed INSIDE the original pinning commit, not
      in a separate PR and not newly introduced by TODOs #1–6. The current rename handlers
      and profile-rename test section are byte-identical to HEAD. Removing them now would
      add a behavioral revert to the follow-up diff, not extract an uncommitted change.
      No history rewrite, commit, separate PR, or physical extraction is claimed.

      History/blame and dependency classification:
      - `3c3aafb` introduced profile switching and optimistic profile rename/rollback;
        `3d2495dc` introduced its alert flow. Default-profile protection, name validation,
        optimistic selection persistence, and rename RPC/actions predate pin synchronization.
      - `9b9e116` added `ProfileRenameMutation`, single-rename serialization, targeted
        rollback instead of restoring the entire profile snapshot, and completion-time
        selection checks. Preserving newer selections/profile edits is general rename
        correctness, not intrinsically pin synchronization. These are valid candidates
        for a separately based rename-correctness change, not disposable work.
      - The same committed hunks also invalidate/cancel the active profile fetch, defer
        `load` while the selected name is optimistic, and refetch the selected renamed
        (or restored) profile on completion. They interact with pinning's generation and
        row-provenance requirements: an old response must not reconcile pins and an
        optimistic directory must not establish ownership before rename succeeds.
        Removing only the mutation state/load guard or completion refresh would break
        these dependencies or leave stale provenance blocking pin affordances.
      - `selectionChanged` is currently assigned but never read; it is not a pin safety
        dependency. Removing this committed dead bookkeeping alone would be cleanup,
        not separation or behavior preservation in a different PR; left unchanged.
      - `HermesProfileClientTests` changes in the original commit only add the `pinned`
        decoding fixture/assertion, not rename behavior. Session-title rename fetch
        invalidation is shared stale-response protection, not profile-rename scope creep.

      Existing tests already distinguish the contracts, so no new tests were necessary.
      Ran only these exact `SessionListFeatureTests` names on the approved shared Mac:
      - `activeProfileRenameDefersReplacementFetchAndPreservesNewerSelection` — 4 cases.
      - `failedRenameRestoresCurrentlySelectedOptimisticName` — 2 cases.
      - `renameCustomProfileIsOptimisticWithRollback`.
      - `renameCustomProfileSucceeds`.
      - `renameProfileAlertOpensAndConfirms`.
      - `renameProfileAlertCancelDismisses`.
      - `defaultProfileCannotBeRenamedOrDeleted`.
      - `selectProfilePersistsResetsAndRefetches`.
      - `staleProfileListSuccessAndFailureAreIgnored` — 5 cases.
      - `profileRoundTripAndSearchClearRejectEarlierResponses`.
      - `pinWritesRequireTrustedCurrentProfileRows` — 12 cases.

      Result: **11 tests in 1 suite, 30 executed cases, zero failures**, exit code 0.
      `will@192.168.1.195:~/code/remote/hermes-mobile/HermesKit`, no file copying;
      `swift test --scratch-path "$HOME/Library/Caches/hermes-mobile-swift-build" --filter`
      with the exact selection recorded in `/home/will/.hermes/cache/scratch/todo7-filter.txt`.
      Output: `/home/will/.hermes/cache/scratch/todo7-focused-run.log`.
      No compiler warnings; nonblocking SSH known-host notice only. No broad suite or
      standalone build. These are regression results, not a claimed feature RED/GREEN.

      All tracked and nonignored untracked file hashes matched locally/remotely after the
      run and matched the initial snapshot before this plan-only edit. Original dirty
      `HermesKit/Package.resolved` remained byte-for-byte unchanged (runner caused no churn),
      SHA-256 `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`.
      `PushAppDelegate.swift`, AppleDouble files, and all existing follow-up work preserved.
      `git diff --check` passed. Only TODO #7 in this plan changed; no commit/push.
      Nonblocking follow-up: if a literal PR split is required, obtain authorization to
      reconstruct separate rename-correctness and pin-sync commits from `bea4cc0`, port
      their shared fetch/provenance dependencies, and rerun these regressions. Reverting
      committed rename behavior in this dirty worktree is not a safe substitute.

- [x] **8. Tighten documentation and repository-style naming.**
      **Complete.** Reduced the session-list pin rule in `CLAUDE.md` to the concise invariant:
      shared membership/device-local order, trusted capable profile-backed rows only, legacy
      local preservation, no ownership inference from search/cache, and a pointer to the full
      migration/fallback/pending-write/rollback/refresh contract in
      `docs/features/session-list.md`. Kept archive/rename/delete guidance separate.

      Updated `docs/features/session-list.md` to document the verified pin invariants:
      migration before server unpins, legacy and nil-capability local fallback, ownership before
      capability, search safety, local ordering, per-ID concurrency and rollback, removal
      feedback, and refresh/search restart behavior.

      Repository naming review found the existing commit and open PR title
      `feat(session-list): sync profile-scoped pins with server` does not match the repository's
      current capitalized-verb/no-prefix convention. Recommended title: `Sync profile-scoped
      pins with the server`. Renaming PR metadata would not rewrite history; renaming the
      already-published commit would require an authorized history rewrite, so neither was
      changed here.

      Verification: `git diff --check` and Markdown whitespace/final-newline checks passed.
      No configured documentation validator or Markdown linter exists; no Swift tests were
      needed for documentation-only changes. Only `CLAUDE.md`, the pin section of
      `docs/features/session-list.md`, and this TODO entry changed. Production/tests,
      `Package.resolved`, `PushAppDelegate.swift`, and AppleDouble files were preserved.
      No commit/push.
- [x] **9. Run regression verification and perform final review.**
      **Complete.** Focused regression verification, full package verification, scope inspection,
      and independent final review are complete. No commit, push, or PR metadata change was
      made.

      Final review found and fixed three concrete blockers with strict TDD:
      - capability-upgrade migration after nil-only responses;
      - mixed nil/explicit capability responses enrolling later local-fallback pins; and
      - migration bypassing pending archived-delete guards.
      The fixes preserve profile/query/generation provenance, durable checkpoint identity and
      retry behavior, local ordering, per-ID rollback, search ownership safety, and unrelated-row
      actionability. The reverse archived-delete race is also covered: parent-owned pending
      generations and presented-child deletion state block both user pin changes and automatic
      migration until the exact delete request finishes.

      Focused verification on the approved shared Mac, using the external SwiftPM scratch path
      `$HOME/Library/Caches/hermes-mobile-swift-build`, passed:
      - capability/migration fix: **13 tests in 2 suites, 26 cases, zero failures**;
      - archived-delete race fix: **12 tests, 22 cases, zero failures**; and
      - final combined blocker regression selection: **24 tests in 2 suites, 86 cases, zero
        failures**, exit code 0.
      RED runs were observed before each production fix; exact logs and filters are recorded in
      `/home/will/.hermes/cache/scratch/` (`pin-upgrade-*`, `archived-pin-*`, and
      `blockers-*`). Source hashes matched between the local checkout and Mac before/after the
      final GREEN run. `git diff --check` passed.

      The applicable full HermesKit suite also ran on the Mac: **1512 tests in 67 suites**.
      Pin-related suites passed. The run exited 1 for two pre-existing/environmental issues:
      `liveKeychainRoundTripsBearerSession()` failed with Keychain `.unhandled(-25308)`, and
      `aPersistFailureStillPublishesTheRotatedPair()` recorded its intentional known issue.
      These are unrelated to the pin changes; no full-suite success is claimed.

      Final scope review preserved the unrelated dirty `HermesKit/Package.resolved`,
      `HermesMobile/Sources/PushAppDelegate.swift`, AppleDouble files, and the existing profile
      rename/search-API decisions. The published commit and PR title were not rewritten.
      Original `Package.resolved` SHA-256 remains
      `bf121a8cdfaf4b13064cae28c4a636b9ca57f53e521e354332e9741d6191b740`. Optional lineage-key
      evaluation remains separate and is not included. `TODO #9` is complete.

## Optional follow-up

- [ ] **Optional: evaluate lineage-based pin keys.**
      Investigate the reviewer’s suggestion to key pins on `lineageRootID ?? id` for
      compression rotation. Treat this as optional until the current session-ID behavior and
      migration semantics are understood; do not include it automatically in the required
      PR rework.

## Working rules

- Work on one checklist item at a time, only after the user says to start.
- Preserve unrelated worktree changes and do not commit or push without explicit authorization.
- Do not claim a review item is resolved without targeted evidence.
