//
//  AppLifecycleNotifier.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 9/4/24.
//
import Foundation
import UIKit

typealias cb = () -> ()

protocol AppLifecycleNotifierUseCase {
    func listen(onForeground: @escaping cb, onBackground: @escaping cb)
    func unlisten()
}

class AppLifecycleNotifier {
    private var fromBackground: Bool = false
    private var listenersIds: [NSObjectProtocol] = []
        
    deinit {
        self.unlisten()
    }
}

extension AppLifecycleNotifier: AppLifecycleNotifierUseCase {
    func listen(onForeground: @escaping cb, onBackground: @escaping cb) {
        func _onBackground() {
            self.fromBackground = true
            onBackground()
        }
        
        self.listenersIds.append(
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                if (self.fromBackground) {
                    self.fromBackground = false
                    onForeground()
                }
            }
        )
        
        self.listenersIds.append(
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                _onBackground()
            }
        )

        self.listenersIds.append(
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                _onBackground()
            }
        )
    }
    
    func unlisten() {
        self.listenersIds.forEach { token in
            NotificationCenter.default.removeObserver(token)
        }
        
        self.listenersIds = []
    }
}
