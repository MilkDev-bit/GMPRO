/// @file lib/features/nutrition/presentation/providers/nutrition_provider.dart
/// @description Proveedor Riverpod para la gestión en tiempo real de la dieta IA,
/// conteo de macros, agua y búsqueda sobre el catálogo precargado Open Food Facts.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/nutrition_entities.dart';

/// Perfil de dieta del socio: los datos reales que alimentan la fórmula
/// científica del ai-service. Se persiste (secure storage) y se edita desde
/// el formulario o desde Ajustes.
class DietProfile {
  const DietProfile({
    this.objetivo = 'hipertrofia',
    this.pesoKg = 75.0,
    this.estaturaCm = 175.0,
    this.edad = 25,
    this.actividad = 'moderado',
    this.isComplete = false,
  });

  final String objetivo;
  final double pesoKg;
  final double estaturaCm;
  final int edad;
  final String actividad;

  /// true una vez que el socio guardó/generó con sus propios datos.
  final bool isComplete;

  static const Map<String, String> objetivoLabels = {
    'hipertrofia': 'Hipertrofia',
    'definicion': 'Definición',
    'mantenimiento': 'Mantenimiento',
    'fuerza': 'Fuerza',
  };
  static const Map<String, String> actividadLabels = {
    'sedentario': 'Sedentario',
    'moderado': 'Moderado',
    'activo': 'Activo',
    'muy_activo': 'Muy activo',
  };

  String get objetivoLabel => objetivoLabels[objetivo] ?? objetivo;
  String get actividadLabel => actividadLabels[actividad] ?? actividad;

  DietProfile copyWith({
    String? objetivo,
    double? pesoKg,
    double? estaturaCm,
    int? edad,
    String? actividad,
    bool? isComplete,
  }) {
    return DietProfile(
      objetivo: objetivo ?? this.objetivo,
      pesoKg: pesoKg ?? this.pesoKg,
      estaturaCm: estaturaCm ?? this.estaturaCm,
      edad: edad ?? this.edad,
      actividad: actividad ?? this.actividad,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, dynamic> toJson() => {
        'objetivo': objetivo,
        'pesoKg': pesoKg,
        'estaturaCm': estaturaCm,
        'edad': edad,
        'actividad': actividad,
        'isComplete': isComplete,
      };

  factory DietProfile.fromJson(Map<String, dynamic> j) => DietProfile(
        objetivo: (j['objetivo'] as String?) ?? 'hipertrofia',
        pesoKg: (j['pesoKg'] as num?)?.toDouble() ?? 75.0,
        estaturaCm: (j['estaturaCm'] as num?)?.toDouble() ?? 175.0,
        edad: (j['edad'] as num?)?.toInt() ?? 25,
        actividad: (j['actividad'] as String?) ?? 'moderado',
        isComplete: (j['isComplete'] as bool?) ?? true,
      );
}

class NutritionState {
  const NutritionState({
    this.plan,
    this.isLoading = false,
    this.error,
    this.isSearching = false,
    this.searchResults = const [],
    this.waterConsumedMl = 0,
    this.profile = const DietProfile(),
    this.consumedCalorias = 0,
    this.consumedProteinas = 0,
    this.consumedCarbohidratos = 0,
    this.consumedGrasas = 0,
    this.consumedFoodIds = const {},
    this.logDateIso = '',
  });

  final NutritionPlan? plan;
  final bool isLoading;
  final String? error;
  final bool isSearching;
  final List<FoodItem> searchResults;

  /// Agua bebida HOY (ml), sincronizada con el backend (registros_hidratacion).
  final int waterConsumedMl;

  /// Perfil actual del socio (persistido). isComplete=false hasta que lo configura.
  final DietProfile profile;

  // ── Consumo REAL de hoy (registros_nutricion, vía fitness-service) ──────────
  final int consumedCalorias;
  final double consumedProteinas;
  final double consumedCarbohidratos;
  final double consumedGrasas;

  /// nombre de alimento (minúsculas) → id del registro consumido hoy. Sirve para
  /// mostrar el check y para poder quitarlo (DELETE) al destildar.
  final Map<String, String> consumedFoodIds;

  /// Fecha (yyyy-mm-dd, local) del último consumo cargado. Se usa para el reset
  /// diario: si cambia el día, se recarga y el dashboard vuelve a 0.
  final String logDateIso;

  NutritionState copyWith({
    NutritionPlan? plan,
    bool? isLoading,
    String? error,
    bool? isSearching,
    List<FoodItem>? searchResults,
    int? waterConsumedMl,
    DietProfile? profile,
    int? consumedCalorias,
    double? consumedProteinas,
    double? consumedCarbohidratos,
    double? consumedGrasas,
    Map<String, String>? consumedFoodIds,
    String? logDateIso,
  }) {
    return NutritionState(
      plan:            plan ?? this.plan,
      isLoading:       isLoading ?? this.isLoading,
      error:           error,
      isSearching:     isSearching ?? this.isSearching,
      searchResults:   searchResults ?? this.searchResults,
      waterConsumedMl: waterConsumedMl ?? this.waterConsumedMl,
      profile:         profile ?? this.profile,
      consumedCalorias:       consumedCalorias ?? this.consumedCalorias,
      consumedProteinas:      consumedProteinas ?? this.consumedProteinas,
      consumedCarbohidratos:  consumedCarbohidratos ?? this.consumedCarbohidratos,
      consumedGrasas:         consumedGrasas ?? this.consumedGrasas,
      consumedFoodIds:        consumedFoodIds ?? this.consumedFoodIds,
      logDateIso:             logDateIso ?? this.logDateIso,
    );
  }
}

/// Fecha local en formato yyyy-mm-dd (para comparar días sin la hora).
String _todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

class NutritionNotifier extends StateNotifier<NutritionState> {
  // Arranca SIN plan (plan == null): el dashboard muestra "completa tu perfil"
  // hasta que el usuario genere su dieta con datos reales. Ya NO autogeneramos
  // con valores por defecto ni mostramos el stub.
  NutritionNotifier(this._apiClient, this._storage) : super(const NutritionState()) {
    _loadProfile();
  }

  final ApiClient _apiClient;
  final SecureStorageService _storage;

  // Último perfil usado (se recuerda para recalcular y pre-llenar el formulario).
  String lastObjetivo   = 'hipertrofia';
  double lastPesoKg     = 75.0;
  double lastEstaturaCm = 175.0;
  int    lastEdad       = 25;
  String lastActividad  = 'moderado';

  /// Carga el perfil persistido al arrancar (para prellenar el formulario y que
  /// Ajustes muestre los datos reales del socio) y la última dieta generada, para
  /// que el plan NO desaparezca al reabrir/recompilar la app. No genera dieta sola.
  Future<void> _loadProfile() async {
    final json = await _storage.getDietProfile();
    if (json != null) {
      final p = DietProfile.fromJson(json);
      lastObjetivo   = p.objetivo;
      lastPesoKg     = p.pesoKg;
      lastEstaturaCm = p.estaturaCm;
      lastEdad       = p.edad;
      lastActividad  = p.actividad;
      if (mounted) state = state.copyWith(profile: p);
    }
    // Rehidratar la dieta persistida (JSON crudo de la última generación).
    final planJson = await _storage.getDietPlan();
    if (planJson != null) {
      try {
        final plan = await NutritionPlan.parseInBackground(planJson);
        if (mounted) state = state.copyWith(plan: plan);
        // Con plan restaurado, cargamos el consumo REAL de hoy (calorías/agua).
        unawaited(loadTodayLog());
      } catch (_) {
        // JSON corrupto/incompatible: se ignora, el socio puede regenerar.
      }
    }
  }

  DietProfile get _profileFromLast => DietProfile(
        objetivo: lastObjetivo,
        pesoKg: lastPesoKg,
        estaturaCm: lastEstaturaCm,
        edad: lastEdad,
        actividad: lastActividad,
        isComplete: true,
      );

  Future<void> _persistProfile(DietProfile p) => _storage.saveDietProfile(p.toJson());

  /// Guarda el perfil editado desde Ajustes. Persiste y, si ya existe una dieta
  /// generada, la recalcula con los nuevos datos.
  Future<void> updateProfile({
    String? objetivo,
    double? pesoKg,
    double? estaturaCm,
    int? edad,
    String? actividad,
  }) async {
    lastObjetivo   = objetivo   ?? lastObjetivo;
    lastPesoKg     = pesoKg     ?? lastPesoKg;
    lastEstaturaCm = estaturaCm ?? lastEstaturaCm;
    lastEdad       = edad       ?? lastEdad;
    lastActividad  = actividad  ?? lastActividad;
    final p = _profileFromLast;
    state = state.copyWith(profile: p);
    await _persistProfile(p);
    if (state.plan != null) await generateDietPlan();
  }

  /// Genera o recalcula una dieta PERSONALIZADA desde el ai-service, que aplica
  /// la fórmula científica con los datos reales del socio (peso, estatura, edad,
  /// objetivo, actividad). Los valores nulos conservan el último perfil usado.
  Future<void> generateDietPlan({
    String? objetivo,
    double? pesoKg,
    double? estaturaCm,
    int? edad,
    String? actividad,
  }) async {
    lastObjetivo   = objetivo   ?? lastObjetivo;
    lastPesoKg     = pesoKg     ?? lastPesoKg;
    lastEstaturaCm = estaturaCm ?? lastEstaturaCm;
    lastEdad       = edad       ?? lastEdad;
    lastActividad  = actividad  ?? lastActividad;

    // Persistimos el perfil: queda como fuente de verdad para prellenar el
    // formulario y editarlo desde Ajustes aunque se cierre la app.
    final profile = _profileFromLast;
    unawaited(_persistProfile(profile));

    state = state.copyWith(isLoading: true, error: null, profile: profile);
    try {
      final response = await _apiClient.dio.post(
        // URL ABSOLUTA del ai-service. Antes era relativa → se resolvía contra el
        // baseUrl del dio (auth-service) → 404 → la app se quedaba con el STUB
        // (por eso salían datos mockeados en vez de la dieta calculada real).
        '${AppConfig.aiServiceBaseUrl}/recommendations/diet',
        data: {
          'objetivo':   lastObjetivo,
          'pesoKg':     lastPesoKg,
          'estaturaCm': lastEstaturaCm,
          'edad':       lastEdad,
          'actividad':  lastActividad,
        },
      );

      if (response.data['success'] == true && response.data['data'] != null) {
        final raw = response.data['data'] as Map<String, dynamic>;
        final plan = await NutritionPlan.parseInBackground(raw);
        // Persistimos el JSON crudo: al reabrir/recompilar la app se rehidrata
        // en _loadProfile en vez de perderse (antes solo vivía en memoria).
        unawaited(_storage.saveDietPlan(raw));
        state = state.copyWith(plan: plan, isLoading: false);
        // Al tener plan, cargamos el consumo REAL de hoy (calorías/agua marcadas).
        unawaited(loadTodayLog());
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.data['error'] as String? ?? 'Error al generar la dieta IA',
        );
      }
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _friendlyDioError(e),
      );
    }
  }

  /// Convierte un DioException en un mensaje amigable para el usuario.
  /// Intenta extraer el mensaje del body JSON del backend (que ya viene en español)
  /// y, si no puede, devuelve un fallback claro según el status code.
  static String _friendlyDioError(DioException e) {
    // Intentar extraer el mensaje del body JSON del backend
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['error'] is String) {
      return data['error'] as String;
    }

    // Fallbacks por código HTTP
    switch (e.response?.statusCode) {
      case 429:
        return 'Has alcanzado el límite de generaciones por hoy. '
               'Intenta de nuevo mañana.';
      case 401:
        return 'Tu sesión expiró. Cierra sesión y vuelve a iniciar.';
      case 403:
        return 'No tienes permiso para esta acción. Verifica tu membresía.';
      case 502:
        return 'El servicio de IA no está disponible temporalmente. '
               'Intenta en unos minutos.';
      case 503:
        return 'El servidor está en mantenimiento. Intenta en unos minutos.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          return 'La generación tardó demasiado. Verifica tu conexión e intenta de nuevo.';
        }
        if (e.type == DioExceptionType.connectionError) {
          return 'Sin conexión a internet. Verifica tu red e intenta de nuevo.';
        }
        return 'Error al conectar con el servidor. Intenta de nuevo.';
    }
  }

  Future<void> searchOpenFoodFacts(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: _quickAddSuggestedFoods, isSearching: false);
      return;
    }
    state = state.copyWith(isSearching: true, error: null);
    try {
      final response = await _apiClient.dio.get(
        // URL ABSOLUTA del fitness-service (búsqueda Open Food Facts). Antes
        // relativa → iba al auth-service → 404.
        '${AppConfig.fitnessServiceBaseUrl}/foods/search',
        queryParameters: {'q': query.trim()},
      );

      if (response.data['success'] == true && response.data['data'] != null) {
        final list = response.data['data'] as List<dynamic>;
        final items = await FoodItem.parseListInBackground(list);
        state = state.copyWith(searchResults: items, isSearching: false);
      } else {
        state = state.copyWith(
          searchResults: _quickAddSuggestedFoods,
          isSearching: false,
        );
      }
    } catch (_) {
      // Fallback in-memory en caso de desconexión
      final qLower = query.toLowerCase();
      final filtered = _quickAddSuggestedFoods.filter(
        (f) =>
            f.nombre.toLowerCase().contains(qLower) ||
            f.marca.toLowerCase().contains(qLower) ||
            f.codigoBarras.contains(qLower),
      );
      state = state.copyWith(searchResults: filtered, isSearching: false);
    }
  }

  /// Agrega un alimento específico a una comida y recalcula todos los macros.
  void addFoodToMeal(String mealId, FoodItem food) {
    if (state.plan == null) return;
    final currentMeals = List<Meal>.from(state.plan!.comidas);
    final index = currentMeals.indexWhere((m) => m.id == mealId);
    if (index != -1) {
      final targetMeal = currentMeals[index];
      final updatedAlimentos = List<FoodItem>.from(targetMeal.alimentos)..add(food);
      currentMeals[index] = targetMeal.copyWith(alimentos: updatedAlimentos);
      state = state.copyWith(plan: state.plan!.copyWith(comidas: currentMeals));
    }
  }

  /// Elimina un alimento de una comida por su código de barras.
  void removeFoodFromMeal(String mealId, String codigoBarras) {
    if (state.plan == null) return;
    final currentMeals = List<Meal>.from(state.plan!.comidas);
    final index = currentMeals.indexWhere((m) => m.id == mealId);
    if (index != -1) {
      final targetMeal = currentMeals[index];
      final updatedAlimentos = List<FoodItem>.from(targetMeal.alimentos)
        ..removeWhere((f) => f.codigoBarras == codigoBarras);
      currentMeals[index] = targetMeal.copyWith(alimentos: updatedAlimentos);
      state = state.copyWith(plan: state.plan!.copyWith(comidas: currentMeals));
    }
  }

  /// Registra consumo de agua en ml.
  // ── SEGUIMIENTO REAL (fitness-service: registros_nutricion + hidratación) ────

  /// Carga el consumo REAL de hoy (calorías/macros + agua + alimentos marcados)
  /// desde el backend. Se llama al abrir la pantalla de nutrición.
  Future<void> loadTodayLog() async {
    try {
      final res = await _apiClient.dio.get('${AppConfig.fitnessServiceBaseUrl}/nutrition/today');
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null) return;
      final s = (data['summary'] as Map<String, dynamic>?) ?? const {};
      final entries = (data['entries'] as List<dynamic>?) ?? const [];
      final map = <String, String>{};
      for (final e in entries) {
        final m = e as Map<String, dynamic>;
        final nombre = (m['nombre_alimento'] as String?)?.toLowerCase().trim();
        if (nombre != null && nombre.isNotEmpty) map[nombre] = m['id'].toString();
      }
      state = state.copyWith(
        consumedCalorias:      (s['calorias'] as num?)?.toInt() ?? 0,
        consumedProteinas:     (s['proteinas'] as num?)?.toDouble() ?? 0,
        consumedCarbohidratos: (s['carbohidratos'] as num?)?.toDouble() ?? 0,
        consumedGrasas:        (s['grasas'] as num?)?.toDouble() ?? 0,
        waterConsumedMl:       (s['agua_ml'] as num?)?.toInt() ?? 0,
        consumedFoodIds:       map,
        logDateIso:            _todayIso(),
      );
    } catch (_) {
      // Sin bloquear la UI: si falla, el dashboard queda en 0 (nada consumido aún).
    }
  }

  /// Reset diario: si cambió el día desde la última carga (o nunca se cargó),
  /// recarga el consumo. El backend está keyed por CURRENT_DATE, así que el día
  /// nuevo llega en 0 y el dashboard se "resetea" visualmente solo.
  Future<void> ensureTodayFresh() async {
    if (state.logDateIso != _todayIso()) {
      await loadTodayLog();
    }
  }

  /// Suma agua al total de hoy: optimista en UI + sincroniza con el backend.
  Future<void> addWater(int ml) async {
    final optimistic = state.waterConsumedMl + ml;
    state = state.copyWith(waterConsumedMl: optimistic);
    try {
      final res = await _apiClient.dio.post(
        '${AppConfig.fitnessServiceBaseUrl}/nutrition/water',
        data: {'ml': ml},
      );
      final total = (res.data['data']?['agua_ml'] as num?)?.toInt();
      if (total != null) state = state.copyWith(waterConsumedMl: total);
    } catch (_) {
      // Se conserva el valor optimista; se re-sincroniza al recargar.
    }
  }

  /// Marca/desmarca un alimento como consumido HOY (sincronizado). Actualiza los
  /// totales de consumo con el summary que devuelve el backend.
  Future<void> toggleFoodConsumed(FoodItem food, String comidaTipo) async {
    final key = food.nombre.toLowerCase().trim();
    final existingId = state.consumedFoodIds[key];
    try {
      Map<String, dynamic>? summary;
      final newMap = Map<String, String>.from(state.consumedFoodIds);
      if (existingId != null) {
        final res = await _apiClient.dio.delete('${AppConfig.fitnessServiceBaseUrl}/nutrition/food/$existingId');
        summary = res.data['data']?['summary'] as Map<String, dynamic>?;
        newMap.remove(key);
      } else {
        final res = await _apiClient.dio.post(
          '${AppConfig.fitnessServiceBaseUrl}/nutrition/food',
          data: {
            'comida': comidaTipo,
            'nombreAlimento': food.nombre,
            'cantidadGramos': food.porcionG,
            'calorias': food.calorias,
            'proteinas': food.proteinas,
            'carbohidratos': food.carbohidratos,
            'grasas': food.grasas,
            'codigoBarras': food.codigoBarras,
          },
        );
        summary = res.data['data']?['summary'] as Map<String, dynamic>?;
        final id = res.data['data']?['row']?['id'];
        if (id != null) newMap[key] = id.toString();
      }
      state = state.copyWith(
        consumedFoodIds: newMap,
        consumedCalorias:      (summary?['calorias'] as num?)?.toInt() ?? state.consumedCalorias,
        consumedProteinas:     (summary?['proteinas'] as num?)?.toDouble() ?? state.consumedProteinas,
        consumedCarbohidratos: (summary?['carbohidratos'] as num?)?.toDouble() ?? state.consumedCarbohidratos,
        consumedGrasas:        (summary?['grasas'] as num?)?.toDouble() ?? state.consumedGrasas,
        waterConsumedMl:       (summary?['agua_ml'] as num?)?.toInt() ?? state.waterConsumedMl,
      );
    } catch (_) {
      // best-effort; el estado se re-sincroniza al recargar.
    }
  }

  /// Catálogo rápido de sugerencias Open Food Facts
  static final List<FoodItem> _quickAddSuggestedFoods = [
    const FoodItem(
      codigoBarras: '7501008012345',
      nombre: 'Avena Integral en Hojuelas',
      marca: 'Quaker',
      porcionG: 80,
      calorias100g: 370,
      proteinas100g: 13.5,
      carbohidratos100g: 66.0,
      grasas100g: 7.0,
    ),
    const FoodItem(
      codigoBarras: '7501000111111',
      nombre: 'Pechuga de Pollo Fresca sin Piel',
      marca: 'Bachoco',
      porcionG: 150,
      calorias100g: 165,
      proteinas100g: 31.0,
      carbohidratos100g: 0.0,
      grasas100g: 3.6,
    ),
    const FoodItem(
      codigoBarras: '7501020304050',
      nombre: 'Atún en Agua en Trozos',
      marca: 'Dolores',
      porcionG: 130,
      calorias100g: 110,
      proteinas100g: 26.0,
      carbohidratos100g: 0.0,
      grasas100g: 0.8,
    ),
    const FoodItem(
      codigoBarras: '7501099998888',
      nombre: 'Arroz Súper Extra Integral Cocido',
      marca: 'Verde Valle',
      porcionG: 150,
      calorias100g: 130,
      proteinas100g: 2.8,
      carbohidratos100g: 28.0,
      grasas100g: 0.8,
    ),
    const FoodItem(
      codigoBarras: '7501234567890',
      nombre: 'Proteína Whey Gold Standard 100% Isolate',
      marca: 'Optimum Nutrition',
      porcionG: 32,
      calorias100g: 388,
      proteinas100g: 78.0,
      carbohidratos100g: 9.7,
      grasas100g: 3.2,
    ),
    const FoodItem(
      codigoBarras: '0000000001234',
      nombre: 'Plátano Tabasco Fresco',
      marca: 'Natural Orgánico',
      porcionG: 120,
      calorias100g: 89,
      proteinas100g: 1.1,
      carbohidratos100g: 22.8,
      grasas100g: 0.3,
    ),
    const FoodItem(
      codigoBarras: '7501444455555',
      nombre: 'Crema de Cacahuate Natural sin Azúcar',
      marca: 'Aladino',
      porcionG: 30,
      calorias100g: 588,
      proteinas100g: 25.0,
      carbohidratos100g: 20.0,
      grasas100g: 50.0,
    ),
  ];

}

extension on List<FoodItem> {
  List<FoodItem> filter(bool Function(FoodItem) test) {
    return where(test).toList();
  }
}

final nutritionProvider = StateNotifierProvider<NutritionNotifier, NutritionState>((ref) {
  final api = ref.watch(apiClientProvider);
  final storage = ref.watch(secureStorageProvider);
  return NutritionNotifier(api, storage);
});
