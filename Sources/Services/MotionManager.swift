import Foundation
import Combine
import CoreMotion

final class MotionManager: ObservableObject {
    private let manager = CMMotionManager()
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let m = motion else { return }
            let smooth = 0.15
            self.pitch += smooth * (m.attitude.pitch - self.pitch)
            self.roll  += smooth * (m.attitude.roll  - self.roll)
        }
    }

    func pause() {
        CrashLogger.shared.mark("Motion", "pause")
        manager.stopDeviceMotionUpdates()
    }

    func resume() {
        guard manager.isDeviceMotionAvailable else { return }
        CrashLogger.shared.mark("Motion", "resume")
        if !manager.isDeviceMotionActive {
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let m = motion else { return }
                let smooth = 0.15
                self.pitch += smooth * (m.attitude.pitch - self.pitch)
                self.roll  += smooth * (m.attitude.roll  - self.roll)
            }
        }
    }
}
