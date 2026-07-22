//
//  LiveActivityBridge.swift
//  GymPro — Puente ActivityKit ⇄ Flutter (MethodChannel)
//
//  Target: Runner.
//
//  Canal: "gympro/live_activity"
//  Métodos:
//    isSupported() -> Bool
//    start(routineName, startedAtEpochMs, state{...}) -> String? (activityId)
//    update(state{...}) -> Bool
//    end(dismissImmediately: Bool) -> Bool
//
//  BATERÍA: `update` usa `staleDate` para que iOS atenúe la actividad si la app
//  deja de reportar, y no se envía ninguna actualización periódica: la cuenta
//  atrás la renderiza el sistema con `Text(timerInterval:)`.
//

import ActivityKit
import Flutter
import Foundation

@available(iOS 16.1, *)
final class LiveActivityBridge {

    static let shared = LiveActivityBridge()
    private init() {}

    private var activity: Activity<GymProWorkoutAttributes>?

    // MARK: - Registro del canal

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "gympro/live_activity",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            if #available(iOS 16.1, *) {
                LiveActivityBridge.shared.handle(call, result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED_OS",
                                    message: "Live Activities requiere iOS 16.1+",
                                    details: nil))
            }
        }
    }

    // MARK: - Dispatcher

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "isSupported":
            result(ActivityAuthorizationInfo().areActivitiesEnabled)

        case "start":
            guard let args = call.arguments as? [String: Any],
                  let stateMap = args["state"] as? [String: Any] else {
                result(FlutterError(code: "BAD_ARGS", message: "Falta 'state'", details: nil))
                return
            }
            let routineName = args["routineName"] as? String ?? "Entrenamiento"
            let startedAtMs = args["startedAtEpochMs"] as? Double ?? Date().timeIntervalSince1970 * 1000
            startActivity(
                routineName: routineName,
                startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
                state: Self.decodeState(stateMap),
                result: result
            )

        case "update":
            guard let args = call.arguments as? [String: Any],
                  let stateMap = args["state"] as? [String: Any] else {
                result(FlutterError(code: "BAD_ARGS", message: "Falta 'state'", details: nil))
                return
            }
            updateActivity(state: Self.decodeState(stateMap), result: result)

        case "end":
            let args = call.arguments as? [String: Any]
            let immediate = args?["dismissImmediately"] as? Bool ?? false
            endActivity(dismissImmediately: immediate, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Mapeo Dart → Swift

    private static func decodeState(_ map: [String: Any]) -> GymProWorkoutAttributes.ContentState {
        // `restEndsAtEpochMs` viaja como fecha ABSOLUTA (no como segundos restantes),
        // para que el sistema pueda animar la cuenta atrás sin más mensajes.
        var restEndsAt: Date?
        if let ms = map["restEndsAtEpochMs"] as? Double, ms > 0 {
            restEndsAt = Date(timeIntervalSince1970: ms / 1000)
        }
        return GymProWorkoutAttributes.ContentState(
            currentExercise: map["currentExercise"] as? String ?? "",
            nextExercise:    map["nextExercise"] as? String ?? "",
            setsDone:        map["setsDone"] as? Int ?? 0,
            setsTotal:       map["setsTotal"] as? Int ?? 0,
            isResting:       map["isResting"] as? Bool ?? false,
            restEndsAt:      restEndsAt,
            accentHex:       map["accentHex"] as? String ?? "#00F0FF"
        )
    }

    // MARK: - Ciclo de vida de la actividad

    private func startActivity(
        routineName: String,
        startedAt: Date,
        state: GymProWorkoutAttributes.ContentState,
        result: @escaping FlutterResult
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "NOT_ENABLED",
                                message: "El usuario desactivó las Live Activities",
                                details: nil))
            return
        }

        // Si ya hay una actividad viva, la reutilizamos (evita duplicados en la Isla).
        if let existing = activity {
            Task {
                await existing.update(using: state)
                result(existing.id)
            }
            return
        }

        let attributes = GymProWorkoutAttributes(routineName: routineName, startedAt: startedAt)
        do {
            let act = try Activity<GymProWorkoutAttributes>.request(
                attributes: attributes,
                contentState: state,
                pushType: nil // Actualizaciones locales; sin APNs (no gasta red).
            )
            activity = act
            result(act.id)
        } catch {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func updateActivity(
        state: GymProWorkoutAttributes.ContentState,
        result: @escaping FlutterResult
    ) {
        guard let activity = activity else {
            result(false)
            return
        }
        Task {
            if #available(iOS 16.2, *) {
                // staleDate: si la app deja de reportar, iOS marca la actividad como
                // obsoleta en vez de mostrar datos viejos indefinidamente.
                let stale = state.restEndsAt?.addingTimeInterval(60)
                    ?? Date().addingTimeInterval(15 * 60)
                await activity.update(
                    ActivityContent(state: state, staleDate: stale)
                )
            } else {
                await activity.update(using: state)
            }
            result(true)
        }
    }

    private func endActivity(dismissImmediately: Bool, result: @escaping FlutterResult) {
        guard let activity = activity else {
            result(false)
            return
        }
        Task {
            let policy: ActivityUIDismissalPolicy = dismissImmediately ? .immediate : .default
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: policy)
            } else {
                await activity.end(dismissalPolicy: policy)
            }
            self.activity = nil
            result(true)
        }
    }
}
