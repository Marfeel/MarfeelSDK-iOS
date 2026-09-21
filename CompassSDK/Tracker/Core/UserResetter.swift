//
//  UserResetter.swift
//  CompassSDK
//
//  The sign-out reset: turns this device into a **new visitor**.
//

import Foundation

/// The synchronous half of `resetUser()`: turns the persisted user into a brand-new
/// visitor through the SDK's **real** first-visit path rather than a re-implementation.
///
/// Order matters:
///  1. The local CDP wipe goes **first**: it reads the live master_id to pick the
///     mid-scoped buckets (segments, server mirrors, meters) it has to clear, and the
///     storage reset would have deleted that id already. It never re-resolves.
///  2. The storage reset blanks every user- and visit-scoped field (last visit included,
///     so `lv` never inherits the previous user's) but keeps the CMP consent.
///  3. The new internal user id, first visit and session are minted eagerly, and the
///     running page's track info is re-pointed at them, so a beacon fired right after
///     already carries the new `u`, `fv`, `t` and `s`.
internal final class UserRotation {
    private let clearCdpIdentity: () -> Void
    private let resetStorage: () -> Void
    private let rebootstrapTrackInfo: () -> Void

    init(clearCdpIdentity: @escaping () -> Void, resetStorage: @escaping () -> Void, rebootstrapTrackInfo: @escaping () -> Void) {
        self.clearCdpIdentity = clearCdpIdentity
        self.resetStorage = resetStorage
        self.rebootstrapTrackInfo = rebootstrapTrackInfo
    }

    func rotate() {
        clearCdpIdentity()
        resetStorage()
        rebootstrapTrackInfo()
    }
}

/// Makes this device a new visitor. Called by hand on sign-out — deliberately **not**
/// inferred from `setSiteUserId(nil)`, which integrations send on every anonymous pageview.
///
/// Load-bearing decisions (each from a real sign-out; do not "simplify" them away):
///
/// 1. **Rotate locally before calling the server.** A beacon can fire while the remote
///    tail is in flight; one carrying the *old* user id would re-create the identity the
///    reset is deleting. Rotating first means such a beacon carries the new id.
/// 2. **Rotation is synchronous**, in the caller's thread, before `start()` returns —
///    callers get it whether or not they wait for the completion.
/// 3. **No precondition.** A user identified only via `Cdp.setIdentity` never has a site
///    user id; every step is idempotent, so the only cost of a duplicate run is rotating
///    an already-anonymous visitor.
/// 4. **An in-flight run is shared, not skipped**, so a second caller waits for the same
///    reset instead of completing early and navigating away.
/// 5. **No identity re-resolve** in here — the next `trackNewPage` does that; minting a
///    master here would orphan one on every duplicate reset.
/// 6. **The remote tail is raced against a timer and never fails the caller.** A failure
///    propagating out would skip the caller's own sign-out step — worse than an
///    incomplete remote reset.
internal final class UserResetter {
    /// One reset run: completes once, either when the remote tail answers or when the
    /// timer fires, whichever comes first. Completions run on a background queue.
    final class Run {
        private let lock = NSLock()
        private var completed = false
        private var completions: [() -> Void] = []

        var isCompleted: Bool { lock.lock(); defer { lock.unlock() }; return completed }

        func onComplete(_ completion: @escaping () -> Void) {
            lock.lock()
            if completed {
                lock.unlock()
                completion()
                return
            }
            completions.append(completion)
            lock.unlock()
        }

        fileprivate func complete() -> Bool {
            lock.lock()
            guard !completed else { lock.unlock(); return false }
            completed = true
            let callbacks = completions
            completions = []
            lock.unlock()
            callbacks.forEach { $0() }
            return true
        }
    }

    private let rotateLocalUser: () -> Void
    private let clearRemoteState: (_ completion: @escaping () -> Void) -> Void
    private let remoteTimeout: TimeInterval
    private let timerQueue: DispatchQueue

    private let lock = NSLock()
    private var inFlight: Run?

    init(
        rotateLocalUser: @escaping () -> Void,
        clearRemoteState: @escaping (_ completion: @escaping () -> Void) -> Void,
        remoteTimeout: TimeInterval = REMOTE_CLEANUP_TIMEOUT,
        timerQueue: DispatchQueue = DispatchQueue.global(qos: .utility)
    ) {
        self.rotateLocalUser = rotateLocalUser
        self.clearRemoteState = clearRemoteState
        self.remoteTimeout = remoteTimeout
        self.timerQueue = timerQueue
    }

    /// Runs the synchronous local rotation (unless a reset is already in flight) and
    /// returns the run to wait on. Never throws.
    @discardableResult
    func start() -> Run {
        lock.lock()
        if let run = inFlight {
            lock.unlock()
            return run
        }
        let run = Run()
        inFlight = run
        lock.unlock()

        rotateLocalUser()

        let finish: () -> Void = { [weak self] in
            guard run.complete() else { return }
            self?.lock.lock()
            if self?.inFlight === run { self?.inFlight = nil }
            self?.lock.unlock()
        }
        timerQueue.asyncAfter(deadline: .now() + remoteTimeout, execute: finish)
        clearRemoteState(finish)

        return run
    }

    /// Rotates (or joins the in-flight run) and calls `completion` once it settles.
    func reset(completion: (() -> Void)? = nil) {
        let run = start()
        if let completion = completion { run.onComplete(completion) }
    }
}
