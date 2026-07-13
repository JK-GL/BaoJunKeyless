import Foundation
import Combine
import CoreMotion
import UIKit

@MainActor
final class MotionManager: ObservableObject {
    private enum UpdateMode: Equatable {
        case active
        case settling
        case idle
    }

    private let manager = CMMotionManager()
    @Published private(set) var pitch: Double = 0
    @Published private(set) var roll: Double = 0

    private let smoothingFactor = 0.18
    private let activeThreshold = 0.020
    private let settlingThreshold = 0.004
    private let publishEpsilon = 0.0005

    private let activeFPS: Int
    private var updateMode: UpdateMode = .settling
    private var currentInterval: TimeInterval = 0
    private var stableSampleCount = 0
    private var lastRawPitch: Double = 0
    private var lastRawRoll: Double = 0

    init() {
        activeFPS = max(UIScreen.main.maximumFramesPerSecond, 60)
        guard manager.isDeviceMotionAvailable else { return }
        startUpdates(mode: .settling)
    }

    func pause() {
        // CrashLogger.shared.mark("Motion", "pause") // routine
        manager.stopDeviceMotionUpdates()
        currentInterval = 0
    }

    func resume() {
        guard manager.isDeviceMotionAvailable else { return }
        // CrashLogger.shared.mark("Motion", "resume") // routine
        stableSampleCount = 0
        if !manager.isDeviceMotionActive {
            startUpdates(mode: .settling)
        }
    }

    private func startUpdates(mode: UpdateMode) {
        let interval = interval(for: mode)
        if manager.isDeviceMotionActive, updateMode == mode, abs(currentInterval - interval) < 0.0001 {
            return
        }

        updateMode = mode
        currentInterval = interval
        stableSampleCount = 0

        manager.stopDeviceMotionUpdates()
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            self?.handleMotionSample(motion)
        }
    }

    private func handleMotionSample(_ motion: CMDeviceMotion?) {
        guard let motion else { return }

        let rawPitch = motion.attitude.pitch
        let rawRoll = motion.attitude.roll
        let delta = max(abs(rawPitch - lastRawPitch), abs(rawRoll - lastRawRoll))

        lastRawPitch = rawPitch
        lastRawRoll = rawRoll

        let nextMode = nextMode(for: delta)
        if nextMode != updateMode {
            startUpdates(mode: nextMode)
        }

        let nextPitch = pitch + smoothingFactor * (rawPitch - pitch)
        let nextRoll = roll + smoothingFactor * (rawRoll - roll)
        let publishDelta = max(abs(nextPitch - pitch), abs(nextRoll - roll))

        if updateMode != .idle || publishDelta > publishEpsilon {
            pitch = nextPitch
            roll = nextRoll
        }
    }

    private func nextMode(for delta: Double) -> UpdateMode {
        if delta >= activeThreshold {
            stableSampleCount = 0
            return .active
        }

        if delta >= settlingThreshold {
            stableSampleCount = 0
            return .settling
        }

        stableSampleCount += 1
        if stableSampleCount >= idleSampleThreshold(for: updateMode) {
            return .idle
        }
        return .settling
    }

    private func interval(for mode: UpdateMode) -> TimeInterval {
        switch mode {
        case .active:
            return 1.0 / Double(activeFPS)
        case .settling:
            return 1.0 / 30.0
        case .idle:
            return 1.0 / 5.0
        }
    }

    private func idleSampleThreshold(for mode: UpdateMode) -> Int {
        switch mode {
        case .active:
            return max(activeFPS / 8, 8)
        case .settling:
            return 10
        case .idle:
            return 1
        }
    }
}
