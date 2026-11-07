// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation
import SharedUI

@MainActor @Observable public final class PingModel {
    public enum Phase: Equatable { case idle, resolving, running, finished, stopped(reason: String?), failed(String) }

    public typealias ResolveFunction = @Sendable (String, AddressPreference) async throws -> ResolvedTarget

    public var targetText: String = ""
    public internal(set) var phase: Phase = .idle
    public internal(set) var resolved: ResolvedTarget?
    public internal(set) var samples: [PingSample] = []
    public internal(set) var stats: PingStatistics = PingStatistics(samples: [PingSample]())
    /// Set when the run failed before or during probing; the view shows it as an error state or inline.
    public internal(set) var error: ToolError?
    /// Payload size used by the current/last run (after IPv6 clamping).
    public internal(set) var payloadSize: Int = PingOptions.default.payloadSize
    /// The text the current/last run was started with.
    public internal(set) var runTarget: String = ""

    @ObservationIgnored let service: any PingService
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let router: AppRouter?
    @ObservationIgnored let resolve: ResolveFunction
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    public var recentsStore: RecentsStore { recents }

    public init(service: any PingService, settings: SettingsStore, recents: RecentsStore,
                router: AppRouter? = nil,
                resolve: @escaping ResolveFunction = { try await Resolver.resolve($0, preference: $1) }) {
        self.service = service
        self.settings = settings
        self.recents = recents
        self.router = router
        self.resolve = resolve
    }

    public var isBusy: Bool { phase == .resolving || phase == .running }
    var hasResults: Bool { !samples.isEmpty }

    /// Validates, resolves, records the recent and streams samples. Does nothing while a run is active.
    public func start() {
        guard !isBusy else { return }
        let input = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        guard TargetParser.parse(input, mode: .host) != nil else {
            reset()
            runTarget = input
            fail(ToolError(.invalidTarget(input)))
            return
        }
        reset()
        runTarget = input
        phase = .resolving
        generation += 1
        let gen = generation
        let preference = settings.addressPreference
        let baseOptions = settings.ping
        let resolve = self.resolve
        task = Task { [weak self] in
            do {
                var options = baseOptions
                let target = try await resolve(input, preference)
                try Task.checkCancellation()
                guard let self, self.generation == gen else { return }
                if target.address.family == .v6 { options.payloadSize = min(options.payloadSize, 1452) }
                self.resolved = target
                self.payloadSize = options.payloadSize
                self.phase = .running
                self.recents.record(input, tool: .ping)
                for try await sample in self.service.ping(target, options: options) {
                    guard !Task.isCancelled, self.generation == gen, self.phase == .running else { break }
                    self.append(sample)
                }
                guard !Task.isCancelled, self.generation == gen else { return }
                if self.phase == .running { self.phase = .finished }
            } catch is CancellationError {
                // stop() already set the phase
            } catch {
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                self.handleFailure(error)
            }
        }
    }

    /// Stops the current run, keeping the results. `reason` is shown in the header ("app moved to background").
    public func stop(reason: String? = nil) {
        guard isBusy else { return }
        generation += 1
        task?.cancel()
        task = nil
        phase = phase == .resolving && samples.isEmpty ? .idle : .stopped(reason: reason)
    }

    /// Called by the view when the scene leaves the foreground.
    public func stopForBackground() {
        stop(reason: String(localized: "app moved to background"))
    }

    public func retry() { start() }

    /// Opens the BGP map for the probed address (cross-link, auto-starts).
    public func mapInBGP() {
        guard let address = resolved?.address, address.isPubliclyRoutable else { return }
        router?.open(.bgp, target: address.description, autostart: true)
    }

    /// Whether the current target is a public address (shows "Map in BGP").
    public var canMapInBGP: Bool { resolved?.address.isPubliclyRoutable ?? false }

    /// Picks up a request handed over by the router (cross-links auto-start, recents only pre-fill).
    public func consumePendingRequest() {
        guard let request = router?.takeRequest(for: .ping) else { return }
        if request.autostart {
            if isBusy { stop() }
            targetText = request.target
            start()
        } else if !isBusy {
            targetText = request.target
        }
    }

    /// Plain-text export (DESIGN §4.6).
    public var exportText: String {
        guard hasResults else { return "" }
        return PingExport.text(target: resolved, samples: samples, stats: stats, payloadSize: payloadSize)
    }

    // MARK: - Internals

    private func reset() {
        samples = []
        stats = PingStatistics(samples: [PingSample]())
        resolved = nil
        error = nil
    }

    func append(_ sample: PingSample) {
        if let index = samples.firstIndex(where: { $0.sequence >= sample.sequence }) {
            if samples[index].sequence == sample.sequence { return }
            samples.insert(sample, at: index)
        } else {
            samples.append(sample)
        }
        stats = PingStatistics(samples: samples)
    }

    private func handleFailure(_ error: any Error) {
        fail(ToolError.from(error))
    }

    private func fail(_ toolError: ToolError) {
        error = toolError
        phase = .failed(toolError.title)
    }
}
