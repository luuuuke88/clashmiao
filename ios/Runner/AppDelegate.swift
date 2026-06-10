//
//  AppDelegate.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Wires up all native plugins (one method channel + several event
//  channels) when the Flutter engine spins up. Also seeds the shared
//  filesystem layout so libcore has somewhere to drop its state on
//  first launch.
//

import Flutter
import UIKit
import Libcore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var generatedPluginsRegistered = false
    private var clashMiaoHandlersRegistered = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        seedSharedFilesystem()
        // The explicit-engine path (used by hot-reload + most Flutter
        // template flows) registers plugins via the root
        // FlutterViewController – we forward to that. The implicit
        // engine path is handled in `didInitializeImplicitFlutterEngine`
        // below.
        registerWithImplicitRootControllerIfPresent()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        // Hand the auto-discovered plugins (Flutter standard set) over
        // to the implicit engine, then layer our native handlers on
        // top using the same registry.
        registerGeneratedPlugins(with: engineBridge.pluginRegistry)
        registerClashMiaoHandlers(with: engineBridge.pluginRegistry)
    }

    // MARK: - One-time bootstrap

    /// Make sure the App Group container has the directories libcore
    /// expects, and `chdir` into it so legacy relative-path APIs work.
    private func seedSharedFilesystem() {
        try? FileManager.default.createDirectory(
            at: ProfilePathResolver.runtimeWorkingDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.changeCurrentDirectoryPath(
            ProfilePathResolver.sharedContainer.path
        )
    }

    // MARK: - Plugin registration

    /// Walks the FlutterPluginRegistry and attaches each ClashMiao
    /// plugin to its own registrar. The plugin name string only needs
    /// to be unique within the registry – we use the type name for
    /// readability in crash reports.
    private func registerGeneratedPlugins(with registry: FlutterPluginRegistry) {
        guard !generatedPluginsRegistered else { return }
        GeneratedPluginRegistrant.register(with: registry)
        generatedPluginsRegistered = true
    }

    private func registerClashMiaoHandlers(with registry: FlutterPluginRegistry) {
        guard !clashMiaoHandlersRegistered else { return }
        ChannelMethodHandler.register(with: registry.registrar(forPlugin: "ChannelMethodHandler")!)
        TunnelStatusStream.register(with: registry.registrar(forPlugin: "TunnelStatusStream")!)
        BoxAlertsStream.register(with: registry.registrar(forPlugin: "BoxAlertsStream")!)
        TrafficStatsStream.register(with: registry.registrar(forPlugin: "TrafficStatsStream")!)
        ProxyGroupsStream.register(with: registry.registrar(forPlugin: "ProxyGroupsStream")!)
        LogLinesStream.register(with: registry.registrar(forPlugin: "LogLinesStream")!)
        let registrar = registry.registrar(forPlugin: "PigeonBridge")!
        BoxHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: PigeonBridge())
        clashMiaoHandlersRegistered = true
    }

    /// Some Flutter templates ship with a UIWindowScene + root
    /// FlutterViewController instead of the implicit engine. When that
    /// applies, the implicit-engine callback never fires – so we
    /// register manually using the view controller as the registry.
    private func registerWithImplicitRootControllerIfPresent() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        registerGeneratedPlugins(with: controller)
        registerClashMiaoHandlers(with: controller)
    }
}
