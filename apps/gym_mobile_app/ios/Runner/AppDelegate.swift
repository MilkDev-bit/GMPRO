//
//  AppDelegate.swift
//  GymPro — Runner
//
//  NOTA: este archivo no existía en el repo (el proyecto iOS estaba incompleto).
//  Debe añadirse al target Runner y declararse como delegado en Info.plist
//  (Xcode lo hace automáticamente en un proyecto Flutter estándar).
//

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        GeneratedPluginRegistrant.register(with: self)

        // ── Puente de Live Activities (Isla Dinámica) ─────────────────────
        // Solo se registra en iOS 16.1+; en versiones previas el canal
        // sencillamente no existe y el lado Dart lo detecta con isSupported().
        if #available(iOS 16.1, *) {
            if let registrar = self.registrar(forPlugin: "GymProLiveActivityBridge") {
                LiveActivityBridge.register(with: registrar)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
