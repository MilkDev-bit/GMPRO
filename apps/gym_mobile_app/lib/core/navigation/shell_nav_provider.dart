/// @file lib/core/navigation/shell_nav_provider.dart
/// @description Proveedor Riverpod para el índice de navegación del AppShell.
/// Mantenido a nivel raíz para que la selección de pestaña persista entre rebuilds.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado simple: índice de la pestaña activa (0-4).
final shellNavProvider = StateProvider<int>((ref) => 0);
