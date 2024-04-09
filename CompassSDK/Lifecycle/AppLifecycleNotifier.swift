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
        
        func _onForeground() {
            if (self.fromBackground) {
                self.fromBackground = false
                onForeground()
            }
        }
        
        func observeNotification(forName: NSNotification.Name, cb: @escaping cb) {
            self.listenersIds.append(
                NotificationCenter.default.addObserver(forName: forName, object: nil, queue: .main) { _ in
                    cb()
                }
            )
        }
        
        observeNotification(forName: UIApplication.didBecomeActiveNotification, cb: _onForeground)
        observeNotification(forName: UIApplication.willResignActiveNotification, cb: _onBackground)
        observeNotification(forName: UIApplication.didEnterBackgroundNotification, cb: _onBackground)
    }
    
    func unlisten() {
        self.listenersIds.forEach { token in
            NotificationCenter.default.removeObserver(token)
        }
        
        self.listenersIds = []
    }
}
