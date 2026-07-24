/// @file lib/core/navigation/routine_detail_screen.dart
/// @description Detalle de una rutina abierta por deep link (/routine/:id).
/// Carga desde Isar (Single Source of Truth). Si la rutina no existe localmente,
/// muestra un estado vacío amable con opción de volver al inicio (fallback R4).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../offline/isar_service.dart';
import '../offline/models/local_routine.dart';

class RoutineDetailScreen extends StatelessWidget {
  const RoutineDetailScreen({super.key, required this.routineId});

  final String routineId;

  /// Busca la rutina por su remoteId en Isar (SSoT). Independiente de codegen:
  /// filtra en memoria sobre getAll para no depender de queries generadas.
  Future<LocalRoutine?> _load() async {
    if (!IsarService.instance.isReady) return null;
    final all = await IsarService.instance.getAll<LocalRoutine>();
    for (final r in all) {
      if (r.remoteId == routineId) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rutina')),
      body: FutureBuilder<LocalRoutine?>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final routine = snapshot.data;
          if (routine == null) {
            // Rutina inexistente/borrada: fallback suave (sin pantalla roja).
            return _NotFound(onHome: () => context.go('/'));
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(routine.nombre,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (routine.nivel != null) ...[
                  const SizedBox(height: 4),
                  Text('Nivel: ${routine.nivel}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                // Los ejercicios vienen en JSON (LocalRoutine.ejerciciosJson):
                // aquí los parsea/renderiza tu widget de detalle real.
                Expanded(
                  child: Text(routine.ejerciciosJson,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.onHome});
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 72, color: Colors.white38),
          const SizedBox(height: 12),
          Text('Esta rutina ya no está disponible.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          FilledButton(onPressed: onHome, child: const Text('Ir al inicio')),
        ],
      ),
    );
  }
}
