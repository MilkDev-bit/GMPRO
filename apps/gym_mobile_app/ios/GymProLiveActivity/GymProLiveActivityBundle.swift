//
//  GymProLiveActivityBundle.swift
//  GymPro — Punto de entrada de la Widget Extension.
//
//  Target: GymProLiveActivity (Widget Extension).
//  Xcode genera un archivo equivalente al crear el target; si ya existe uno con
//  @main, ELIMINA uno de los dos (solo puede haber un @main por extensión).
//

import SwiftUI
import WidgetKit

@main
struct GymProLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        // Live Activities requiere iOS 16.1+; en versiones previas la extensión
        // simplemente no expone ningún widget.
        if #available(iOS 16.1, *) {
            GymProLiveActivity()
        }
    }
}
