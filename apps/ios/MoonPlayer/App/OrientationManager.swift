import UIKit

/// 全局屏幕方向锁：普通页面竖屏，播放器可转横屏。
final class OrientationManager {
    static let shared = OrientationManager()

    private(set) var mask: UIInterfaceOrientationMask = .portrait

    func lock(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    func toggle(currentlyLandscape: Bool) {
        lock(currentlyLandscape ? .portrait : .landscape)
    }
}
