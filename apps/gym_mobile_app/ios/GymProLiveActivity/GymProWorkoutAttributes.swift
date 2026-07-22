//
//  GymProWorkoutAttributes.swift
//  GymPro — Live Activity (Isla Dinámica)
//
//  ⚠️ ESTE ARCHIVO DEBE PERTENECER A **AMBOS** TARGETS:
//     • Runner            (para poder iniciar/actualizar la actividad)
//     • GymProLiveActivity (la Widget Extension que la dibuja)
//     En Xcode: selecciona el archivo → File Inspector → Target Membership → marca los dos.
//
//  DISEÑO ORIENTADO A BATERÍA:
//  `restEndsAt` es una FECHA ABSOLUTA, no un contador. La vista usa
//  `Text(timerInterval:)`, de modo que iOS decrementa el cronómetro por su cuenta
//  y NO necesitamos enviar una actualización por segundo desde Flutter.
//  Solo se empuja una actualización cuando cambia el ESTADO (nuevo ejercicio,
//  serie completada, pausa/reanudación), es decir, unas pocas veces por sesión.
//

import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct GymProWorkoutAttributes: ActivityAttributes {

    /// Estado dinámico: lo único que se actualiza durante la sesión.
    public struct ContentState: Codable, Hashable {
        /// Ejercicio en curso (ej. "Press de Banca").
        var currentExercise: String
        /// Siguiente ejercicio; vacío si es el último.
        var nextExercise: String
        /// Series completadas / totales del ejercicio actual.
        var setsDone: Int
        var setsTotal: Int
        /// true = descansando (muestra cuenta atrás); false = ejecutando la serie.
        var isResting: Bool
        /// Instante EXACTO en que termina el descanso. iOS anima la cuenta atrás solo.
        var restEndsAt: Date?
        /// Color de acento en hex (#RRGGBB) según el grupo muscular del día.
        var accentHex: String

        /// Progreso 0…1 del ejercicio actual (para la barra del estado expandido).
        var progress: Double {
            guard setsTotal > 0 else { return 0 }
            return min(1.0, Double(setsDone) / Double(setsTotal))
        }
    }

    // ── Atributos ESTÁTICOS (no cambian en toda la actividad) ──────────────
    /// Nombre de la rutina (ej. "Push Day — Pecho y Tríceps").
    var routineName: String
    /// Momento de inicio de la sesión (para el cronómetro ascendente total).
    var startedAt: Date
}
