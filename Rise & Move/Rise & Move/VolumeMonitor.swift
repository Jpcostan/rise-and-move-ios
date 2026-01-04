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

    var isLow: Bool { outputVolume <= 0.06 }

    func start() {
        let session = AVAudioSession.sharedInstance()

        do {
            // Ambient is lightweight + doesn't interrupt other audio.
            // Activating a session makes outputVolume changes much more reliable.
            try session.setCategory(.ambient, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Non-fatal; we can still read outputVolume.
            print("VolumeMonitor failed to activate session:", error)
        }

        // Refresh immediately
        outputVolume = session.outputVolume

        // Observe system volume changes (side buttons / Control Center)
        volumeObserver?.invalidate()
        volumeObserver = session.observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, _ in
            // Swift 6: KVO callback isn't guaranteed on the main actor.
            // Hop to main safely without creating a concurrent Task that captures self.
            DispatchQueue.main.async {
                self?.outputVolume = session.outputVolume
            }
        }
    }

    func stop() {
        volumeObserver?.invalidate()
        volumeObserver = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Non-fatal.
        }
    }

    deinit {
        volumeObserver?.invalidate()
    }
}
