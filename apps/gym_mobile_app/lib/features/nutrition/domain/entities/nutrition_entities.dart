/// @file lib/features/nutrition/domain/entities/nutrition_entities.dart
/// @description Modelos de dominio para el plan nutricional y macros con
/// integración de códigos de barras de Open Food Facts.

class FoodItem {
  const FoodItem({
    required this.codigoBarras,
    required this.nombre,
    required this.marca,
    required this.porcionG,
    required this.calorias100g,
    required this.proteinas100g,
    required this.carbohidratos100g,
    required this.grasas100g,
    this.esOpenFoodFacts = true,
  });

  final String codigoBarras;
  final String nombre;
  final String marca;
  final double porcionG;
  final double calorias100g;
  final double proteinas100g;
  final double carbohidratos100g;
  final double grasas100g;
  final bool esOpenFoodFacts;

  // ── Cálculos por la porción seleccionada ──────────────────────────────────
  int get calorias => ((calorias100g * porcionG) / 100).round();
  double get proteinas => double.parse(((proteinas100g * porcionG) / 100).toStringAsFixed(1));
  double get carbohidratos => double.parse(((carbohidratos100g * porcionG) / 100).toStringAsFixed(1));
  double get grasas => double.parse(((grasas100g * porcionG) / 100).toStringAsFixed(1));

  FoodItem copyWith({double? porcionG}) {
    return FoodItem(
      codigoBarras: codigoBarras,
      nombre: nombre,
      marca: marca,
      porcionG: porcionG ?? this.porcionG,
      calorias100g: calorias100g,
      proteinas100g: proteinas100g,
      carbohidratos100g: carbohidratos100g,
      grasas100g: grasas100g,
      esOpenFoodFacts: esOpenFoodFacts,
    );
  }

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      codigoBarras: json['codigo_barras'] as String? ?? '0000000000000',
      nombre: json['nombre'] as String? ?? 'Alimento',
      marca: json['marca'] as String? ?? 'Genérico',
      porcionG: (json['porcion_g'] as num?)?.toDouble() ?? 100.0,
      calorias100g: (json['calorias_100g'] as num?)?.toDouble() ?? 0.0,
      proteinas100g: (json['proteinas_100g'] as num?)?.toDouble() ?? 0.0,
      carbohidratos100g: (json['carbohidratos_100g'] as num?)?.toDouble() ?? 0.0,
      grasas100g: (json['grasas_100g'] as num?)?.toDouble() ?? 0.0,
      esOpenFoodFacts: json['es_open_food_facts'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'codigo_barras': codigoBarras,
        'nombre': nombre,
        'marca': marca,
        'porcion_g': porcionG,
        'calorias_100g': calorias100g,
        'proteinas_100g': proteinas100g,
        'carbohidratos_100g': carbohidratos100g,
        'grasas_100g': grasas100g,
        'es_open_food_facts': esOpenFoodFacts,
      };
}

class Meal {
  const Meal({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.horaSugerida,
    required this.alimentos,
  });

  final String id;
  final String tipo; // desayuno, almuerzo, pre_entreno, cena, snacks
  final String nombre;
  final String horaSugerida;
  final List<FoodItem> alimentos;

  int get caloriasTotal => alimentos.fold(0, (sum, f) => sum + f.calorias);
  double get proteinasTotal =>
      double.parse(alimentos.fold(0.0, (sum, f) => sum + f.proteinas).toStringAsFixed(1));
  double get carbohidratosTotal =>
      double.parse(alimentos.fold(0.0, (sum, f) => sum + f.carbohidratos).toStringAsFixed(1));
  double get grasasTotal =>
      double.parse(alimentos.fold(0.0, (sum, f) => sum + f.grasas).toStringAsFixed(1));

  Meal copyWith({List<FoodItem>? alimentos}) {
    return Meal(
      id: id,
      tipo: tipo,
      nombre: nombre,
      horaSugerida: horaSugerida,
      alimentos: alimentos ?? this.alimentos,
    );
  }

  factory Meal.fromJson(Map<String, dynamic> json) {
    final list = json['alimentos'] as List<dynamic>? ?? [];
    return Meal(
      id: json['id'] as String? ?? 'meal_${DateTime.now().millisecondsSinceEpoch}',
      tipo: json['tipo'] as String? ?? 'desayuno',
      nombre: json['nombre'] as String? ?? 'Comida',
      horaSugerida: json['hora_sugerida'] as String? ?? '12:00 PM',
      alimentos: list.map((x) => FoodItem.fromJson(x as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'nombre': nombre,
        'hora_sugerida': horaSugerida,
        'alimentos': alimentos.map((x) => x.toJson()).toList(),
      };
}

class NutritionPlan {
  const NutritionPlan({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.objetivo,
    required this.caloriasMeta,
    required this.proteinasMetaG,
    required this.carbohidratosMetaG,
    required this.grasasMetaG,
    required this.aguaMetaMl,
    required this.comidas,
  });

  final String id;
  final String nombre;
  final String descripcion;
  final String objetivo;
  final int caloriasMeta;
  final int proteinasMetaG;
  final int carbohidratosMetaG;
  final int grasasMetaG;
  final int aguaMetaMl;
  final List<Meal> comidas;

  int get caloriasConsumidas => comidas.fold(0, (sum, m) => sum + m.caloriasTotal);
  double get proteinasConsumidas =>
      double.parse(comidas.fold(0.0, (sum, m) => sum + m.proteinasTotal).toStringAsFixed(1));
  double get carbohidratosConsumidas =>
      double.parse(comidas.fold(0.0, (sum, m) => sum + m.carbohidratosTotal).toStringAsFixed(1));
  double get grasasConsumidas =>
      double.parse(comidas.fold(0.0, (sum, m) => sum + m.grasasTotal).toStringAsFixed(1));

  NutritionPlan copyWith({List<Meal>? comidas}) {
    return NutritionPlan(
      id: id,
      nombre: nombre,
      descripcion: descripcion,
      objetivo: objetivo,
      caloriasMeta: caloriasMeta,
      proteinasMetaG: proteinasMetaG,
      carbohidratosMetaG: carbohidratosMetaG,
      grasasMetaG: grasasMetaG,
      aguaMetaMl: aguaMetaMl,
      comidas: comidas ?? this.comidas,
    );
  }

  factory NutritionPlan.fromJson(Map<String, dynamic> json) {
    final list = json['comidas'] as List<dynamic>? ?? [];
    return NutritionPlan(
      id: json['id'] as String? ?? 'plan_diet_${DateTime.now().millisecondsSinceEpoch}',
      nombre: json['nombre'] as String? ?? 'Dieta AI Coach — Rendimiento & Macros',
      descripcion: json['descripcion'] as String? ?? 'Estrategia calórica ajustada a tu metabolismo.',
      objetivo: json['objetivo'] as String? ?? 'hipertrofia',
      caloriasMeta: (json['calorias_meta'] as num?)?.toInt() ?? 2600,
      proteinasMetaG: (json['proteinas_meta_g'] as num?)?.toInt() ?? 180,
      carbohidratosMetaG: (json['carbohidratos_meta_g'] as num?)?.toInt() ?? 300,
      grasasMetaG: (json['grasas_meta_g'] as num?)?.toInt() ?? 75,
      aguaMetaMl: (json['agua_meta_ml'] as num?)?.toInt() ?? 3500,
      comidas: list.map((x) => Meal.fromJson(x as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'descripcion': descripcion,
        'objetivo': objetivo,
        'calorias_meta': caloriasMeta,
        'proteinas_meta_g': proteinasMetaG,
        'carbohidratos_meta_g': carbohidratosMetaG,
        'grasas_meta_g': grasasMetaG,
        'agua_meta_ml': aguaMetaMl,
        'comidas': comidas.map((x) => x.toJson()).toList(),
      };
}
