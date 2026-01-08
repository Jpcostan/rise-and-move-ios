//
//  VolumeMonitor.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 1/3/26.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VolumeMonitor: ObservableObject {

    /// 0.0 ... 1.0 (device media volume)
    @Published private(set) var outputVolume: Float = AVAudioSession.sharedInstance().outputVolume

    private var volumeObserver: NSKeyValueObservation?
    private var pollCancellable: AnyCancellable?

    // Use a tiny bit of hysteresis to prevent banner flicker near the threshold.
    private let lowThreshold: Float = 0.06
    private let clearThreshold: Float = 0.08

    /// Public low-volume state for UI.
    var isLow: Bool {
        outputVolume <= lowThreshold
    }

    /// Hysteresis-driven "sticky" behavior for calm UI.
    @Published private(set) var isLowStable: Bool = AVAudioSession.sharedInstance().outputVolume <= 0.06

    func start() {
        let session = AVAudioSession.sharedInstance()

        // ✅ IMPORTANT:
        // We can safely *activate* the session to make outputVolume updates reliable,
        // but we must NOT change category/mode and must NEVER deactivate in stop().
        do {
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal; polling still reads a value, just may be less reactive.
            print("VolumeMonitor failed to activate session:", error)
        }

        // Refresh immediately
        refreshVolume(session: session)

        // KVO: observe system volume changes (side buttons / Control Center)
        volumeObserver?.invalidate()
        volumeObserver = session.observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, _ in
            DispatchQueue.main.async {
                self?.refreshVolume(session: session)
            }
        }

        // Polling fallback
        pollCancellable?.cancel()
        pollCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshVolume(session: session)
            }
    }


    func stop() {
        volumeObserver?.invalidate()
        volumeObserver = nil

        pollCancellable?.cancel()
        pollCancellable = nil

        // ✅ IMPORTANT:
        // Do NOT deactivate AVAudioSession here.
        // Deactivating can stop alarm audio that just started.
    }

    private func refreshVolume(session: AVAudioSession) {
        let v = session.outputVolume
        outputVolume = v

        // Hysteresis update for a stable "low volume" banner
        if isLowStable {
            if v >= clearThreshold { isLowStable = false }
        } else {
            if v <= lowThreshold { isLowStable = true }
        }
    }

    deinit {
        volumeObserver?.invalidate()
        pollCancellable?.cancel()
    }
}
