/// @file lib/features/nutrition/presentation/providers/nutrition_provider.dart
/// @description Proveedor Riverpod para la gestión en tiempo real de la dieta IA,
/// conteo de macros, agua y búsqueda sobre el catálogo precargado Open Food Facts.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/nutrition_entities.dart';

class NutritionState {
  const NutritionState({
    this.plan,
    this.isLoading = false,
    this.error,
    this.isSearching = false,
    this.searchResults = const [],
    this.waterConsumedMl = 1750,
  });

  final NutritionPlan? plan;
  final bool isLoading;
  final String? error;
  final bool isSearching;
  final List<FoodItem> searchResults;
  final int waterConsumedMl;

  NutritionState copyWith({
    NutritionPlan? plan,
    bool? isLoading,
    String? error,
    bool? isSearching,
    List<FoodItem>? searchResults,
    int? waterConsumedMl,
  }) {
    return NutritionState(
      plan:            plan ?? this.plan,
      isLoading:       isLoading ?? this.isLoading,
      error:           error,
      isSearching:     isSearching ?? this.isSearching,
      searchResults:   searchResults ?? this.searchResults,
      waterConsumedMl: waterConsumedMl ?? this.waterConsumedMl,
    );
  }
}

class NutritionNotifier extends StateNotifier<NutritionState> {
  NutritionNotifier(this._apiClient) : super(const NutritionState(plan: _defaultStubPlan));

  final ApiClient _apiClient;

  // Evita re-generar en cada rebuild del dashboard: una sola carga por sesión.
  bool _autoLoaded = false;

  /// Carga el plan REAL del backend una vez por sesión (para el card del
  /// dashboard). El backend no expone un GET del plan actual, así que se dispara
  /// la generación vía ai-service en lugar de mostrar el stub por defecto.
  Future<void> ensureTodayPlanLoaded() async {
    if (_autoLoaded || state.isLoading) return;
    _autoLoaded = true;
    await generateDietPlan();
  }

  /// Genera o recalcula una nueva dieta personalizada desde el ai-service.
  Future<void> generateDietPlan({
    String objetivo = 'hipertrofia',
    double pesoKg = 75.0,
    double estaturaCm = 175.0,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/recommendations/diet',
        data: {
          'objetivo': objetivo,
          'pesoKg': pesoKg,
          'estaturaCm': estaturaCm,
        },
      );

      if (response.data['success'] == true && response.data['data'] != null) {
        final plan = await NutritionPlan.parseInBackground(
          response.data['data'] as Map<String, dynamic>,
        );
        state = state.copyWith(plan: plan, isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.data['error'] as String? ?? 'Error al generar la dieta IA',
        );
      }
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Error de conexión. Manteniendo plan de alto rendimiento actual.',
      );
    }
  }

  /// Busca alimentos en catalogo_alimentos de Open Food Facts a través del fitness-service.
  Future<void> searchOpenFoodFacts(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: _quickAddSuggestedFoods, isSearching: false);
      return;
    }
    state = state.copyWith(isSearching: true, error: null);
    try {
      final response = await _apiClient.dio.get(
        '/api/v1/foods/search',
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
  void addWater(int ml) {
    state = state.copyWith(waterConsumedMl: state.waterConsumedMl + ml);
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

  /// Plan nutricional inicial completo con datos de Open Food Facts
  static const NutritionPlan _defaultStubPlan = NutritionPlan(
    id: 'plan_diet_ai_01',
    nombre: 'Hipertrofia Limpia & Rendimiento Óptimo',
    descripcion: 'Reparto calórico 40% carbohidratos, 35% proteína y 25% grasas saludables.',
    objetivo: 'hipertrofia',
    caloriasMeta: 2650,
    proteinasMetaG: 185,
    carbohidratosMetaG: 310,
    grasasMetaG: 75,
    aguaMetaMl: 3500,
    comidas: [
      Meal(
        id: 'meal_desayuno',
        tipo: 'desayuno',
        nombre: 'Desayuno Anabólico — Avena & Huevos',
        horaSugerida: '07:30 AM',
        alimentos: [
          FoodItem(
            codigoBarras: '7501008012345',
            nombre: 'Avena Integral en Hojuelas',
            marca: 'Quaker',
            porcionG: 80,
            calorias100g: 370,
            proteinas100g: 13.5,
            carbohidratos100g: 66.0,
            grasas100g: 7.0,
          ),
          FoodItem(
            codigoBarras: '7501111122222',
            nombre: 'Claras de Huevo Pasteurizadas + 2 Enteros',
            marca: 'San Juan',
            porcionG: 220,
            calorias100g: 95,
            proteinas100g: 12.0,
            carbohidratos100g: 0.8,
            grasas100g: 4.5,
          ),
          FoodItem(
            codigoBarras: '0000000001234',
            nombre: 'Plátano Tabasco en rebanadas',
            marca: 'Natural Orgánico',
            porcionG: 100,
            calorias100g: 89,
            proteinas100g: 1.1,
            carbohidratos100g: 22.8,
            grasas100g: 0.3,
          ),
        ],
      ),
      Meal(
        id: 'meal_almuerzo',
        tipo: 'almuerzo',
        nombre: 'Comida Principal — Pollo y Arroz Integral',
        horaSugerida: '01:30 PM',
        alimentos: [
          FoodItem(
            codigoBarras: '7501000111111',
            nombre: 'Pechuga de Pollo Asada a las Hierbas',
            marca: 'Bachoco',
            porcionG: 180,
            calorias100g: 165,
            proteinas100g: 31.0,
            carbohidratos100g: 0.0,
            grasas100g: 3.6,
          ),
          FoodItem(
            codigoBarras: '7501099998888',
            nombre: 'Arroz Súper Extra Integral Cocido',
            marca: 'Verde Valle',
            porcionG: 180,
            calorias100g: 130,
            proteinas100g: 2.8,
            carbohidratos100g: 28.0,
            grasas100g: 0.8,
          ),
          FoodItem(
            codigoBarras: '0000000009999',
            nombre: 'Aguacate Hass en cubos',
            marca: 'Uruapan Selecto',
            porcionG: 60,
            calorias100g: 160,
            proteinas100g: 2.0,
            carbohidratos100g: 8.5,
            grasas100g: 14.7,
          ),
        ],
      ),
      Meal(
        id: 'meal_pre_entreno',
        tipo: 'pre_entreno',
        nombre: 'Snack Pre-Entrenamiento Explosivo',
        horaSugerida: '05:00 PM',
        alimentos: [
          FoodItem(
            codigoBarras: '7501444455555',
            nombre: 'Crema de Cacahuate Natural',
            marca: 'Aladino',
            porcionG: 25,
            calorias100g: 588,
            proteinas100g: 25.0,
            carbohidratos100g: 20.0,
            grasas100g: 50.0,
          ),
          FoodItem(
            codigoBarras: '7501888899999',
            nombre: 'Yogurt Griego Fresa sin Azúcar',
            marca: 'Chobani',
            porcionG: 150,
            calorias100g: 59,
            proteinas100g: 10.0,
            carbohidratos100g: 3.6,
            grasas100g: 0.2,
          ),
        ],
      ),
      Meal(
        id: 'meal_cena',
        tipo: 'cena',
        nombre: 'Cena de Recuperación Nocturna — Atún & Whey',
        horaSugerida: '09:00 PM',
        alimentos: [
          FoodItem(
            codigoBarras: '7501020304050',
            nombre: 'Atún en Agua en Trozos',
            marca: 'Dolores',
            porcionG: 140,
            calorias100g: 110,
            proteinas100g: 26.0,
            carbohidratos100g: 0.0,
            grasas100g: 0.8,
          ),
          FoodItem(
            codigoBarras: '7501234567890',
            nombre: 'Batido Proteína Whey Gold Standard',
            marca: 'Optimum Nutrition',
            porcionG: 32,
            calorias100g: 388,
            proteinas100g: 78.0,
            carbohidratos100g: 9.7,
            grasas100g: 3.2,
          ),
        ],
      ),
    ],
  );
}

extension on List<FoodItem> {
  List<FoodItem> filter(bool Function(FoodItem) test) {
    return where(test).toList();
  }
}

final nutritionProvider = StateNotifierProvider<NutritionNotifier, NutritionState>((ref) {
  final api = ref.watch(apiClientProvider);
  return NutritionNotifier(api);
});
