//
//  GymProLiveActivity.swift
//  GymPro — Widget Extension (Isla Dinámica + Pantalla de bloqueo)
//
//  Target: GymProLiveActivity (Widget Extension). NO pertenece a Runner.
//
//  Estados cubiertos:
//    • minimal          → píldora mínima cuando hay 2 actividades a la vez
//    • compact leading  → icono/estado
//    • compact trailing → cuenta atrás de descanso o series
//    • expanded         → ejercicio actual, siguiente, progreso y cronómetro
//    • lock screen      → tarjeta completa (banner/pantalla bloqueada)
//
//  BATERÍA: todas las cuentas atrás usan `Text(timerInterval:)`, renderizado por
//  el sistema. No hay Timer ni actualizaciones por segundo desde la app.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Utilidad de color de marca

extension Color {
    /// Crea un Color desde "#RRGGBB" (o "RRGGBB"). Fallback: cian GymPro.
    init(gymProHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else {
            self = Color(red: 0, green: 0.94, blue: 1) // #00F0FF
            return
        }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8)  & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }
}

@available(iOS 16.1, *)
private extension ActivityViewContext where Attributes == GymProWorkoutAttributes {
    var accent: Color { Color(gymProHex: state.accentHex) }
}

// MARK: - Widget principal

@available(iOS 16.1, *)
struct GymProLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GymProWorkoutAttributes.self) { context in

            // ── PANTALLA DE BLOQUEO / BANNER ──────────────────────────────
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(context.accent)

        } dynamicIsland: { context in

            DynamicIsland {
                // ── EXPANDED ──────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EJERCICIO")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.secondary)
                        Text(context.state.currentExercise)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.isResting, let endsAt = context.state.restEndsAt {
                            Text("DESCANSO")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.secondary)
                            // El sistema decrementa este texto sin actualizaciones nuestras.
                            Text(timerInterval: Date.now...endsAt, countsDown: true)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(context.accent)
                                .frame(maxWidth: 90)
                        } else {
                            Text("SERIES")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.secondary)
                            Text("\(context.state.setsDone)/\(context.state.setsTotal)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(context.accent)
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    // Progreso del ejercicio actual.
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(.linear)
                        .tint(context.accent)
                        .padding(.horizontal, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label {
                            Text(context.attributes.routineName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "bolt.fill").foregroundColor(context.accent)
                        }
                        Spacer()
                        if !context.state.nextExercise.isEmpty {
                            Text("Sigue: \(context.state.nextExercise)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }

            } compactLeading: {
                // ── COMPACT (izquierda) ───────────────────────────────────
                Image(systemName: context.state.isResting ? "hourglass" : "figure.strengthtraining.traditional")
                    .foregroundColor(context.accent)

            } compactTrailing: {
                // ── COMPACT (derecha) ─────────────────────────────────────
                if context.state.isResting, let endsAt = context.state.restEndsAt {
                    Text(timerInterval: Date.now...endsAt, countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(context.accent)
                        .frame(maxWidth: 44)
                } else {
                    Text("\(context.state.setsDone)/\(context.state.setsTotal)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(context.accent)
                }

            } minimal: {
                // ── MINIMAL ───────────────────────────────────────────────
                Image(systemName: context.state.isResting ? "hourglass" : "bolt.fill")
                    .foregroundColor(context.accent)
            }
            .keylineTint(context.accent)
        }
    }
}

// MARK: - Vista de pantalla de bloqueo

@available(iOS 16.1, *)
struct LockScreenView: View {
    let context: ActivityViewContext<GymProWorkoutAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Image(systemName: "bolt.fill").foregroundColor(context.accent)
                Text(context.attributes.routineName)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                // Cronómetro total ascendente, también nativo.
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture,
                     countsDown: false)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 60, alignment: .trailing)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.currentExercise)
                        .font(.system(size: 19, weight: .black))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !context.state.nextExercise.isEmpty {
                        Text("Sigue: \(context.state.nextExercise)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if context.state.isResting, let endsAt = context.state.restEndsAt {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("DESCANSO")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.secondary)
                        Text(timerInterval: Date.now...endsAt, countsDown: true)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(context.accent)
                            .frame(maxWidth: 110, alignment: .trailing)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("SERIES")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.secondary)
                        Text("\(context.state.setsDone)/\(context.state.setsTotal)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(context.accent)
                    }
                }
            }

            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
                .tint(context.accent)
        }
        .padding(16)
    }
}
