// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_routine.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalRoutineCollection on Isar {
  IsarCollection<LocalRoutine> get localRoutines => this.collection();
}

const LocalRoutineSchema = CollectionSchema(
  name: r'LocalRoutine',
  id: 4619272854414857241,
  properties: {
    r'completada': PropertySchema(
      id: 0,
      name: r'completada',
      type: IsarType.bool,
    ),
    r'completadaEn': PropertySchema(
      id: 1,
      name: r'completadaEn',
      type: IsarType.dateTime,
    ),
    r'ejerciciosJson': PropertySchema(
      id: 2,
      name: r'ejerciciosJson',
      type: IsarType.string,
    ),
    r'esDelDia': PropertySchema(
      id: 3,
      name: r'esDelDia',
      type: IsarType.bool,
    ),
    r'nivel': PropertySchema(
      id: 4,
      name: r'nivel',
      type: IsarType.string,
    ),
    r'nombre': PropertySchema(
      id: 5,
      name: r'nombre',
      type: IsarType.string,
    ),
    r'remoteId': PropertySchema(
      id: 6,
      name: r'remoteId',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 7,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'usuarioId': PropertySchema(
      id: 8,
      name: r'usuarioId',
      type: IsarType.string,
    )
  },
  estimateSize: _localRoutineEstimateSize,
  serialize: _localRoutineSerialize,
  deserialize: _localRoutineDeserialize,
  deserializeProp: _localRoutineDeserializeProp,
  idName: r'id',
  indexes: {
    r'remoteId': IndexSchema(
      id: 6301175856541681032,
      name: r'remoteId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'remoteId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'usuarioId': IndexSchema(
      id: -6806307564427522310,
      name: r'usuarioId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'usuarioId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'esDelDia': IndexSchema(
      id: 2359432487732103947,
      name: r'esDelDia',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'esDelDia',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _localRoutineGetId,
  getLinks: _localRoutineGetLinks,
  attach: _localRoutineAttach,
  version: '3.3.2',
);

int _localRoutineEstimateSize(
  LocalRoutine object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.ejerciciosJson.length * 3;
  {
    final value = object.nivel;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.nombre.length * 3;
  bytesCount += 3 + object.remoteId.length * 3;
  bytesCount += 3 + object.usuarioId.length * 3;
  return bytesCount;
}

void _localRoutineSerialize(
  LocalRoutine object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.completada);
  writer.writeDateTime(offsets[1], object.completadaEn);
  writer.writeString(offsets[2], object.ejerciciosJson);
  writer.writeBool(offsets[3], object.esDelDia);
  writer.writeString(offsets[4], object.nivel);
  writer.writeString(offsets[5], object.nombre);
  writer.writeString(offsets[6], object.remoteId);
  writer.writeDateTime(offsets[7], object.updatedAt);
  writer.writeString(offsets[8], object.usuarioId);
}

LocalRoutine _localRoutineDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalRoutine();
  object.completada = reader.readBool(offsets[0]);
  object.completadaEn = reader.readDateTimeOrNull(offsets[1]);
  object.ejerciciosJson = reader.readString(offsets[2]);
  object.esDelDia = reader.readBool(offsets[3]);
  object.id = id;
  object.nivel = reader.readStringOrNull(offsets[4]);
  object.nombre = reader.readString(offsets[5]);
  object.remoteId = reader.readString(offsets[6]);
  object.updatedAt = reader.readDateTime(offsets[7]);
  object.usuarioId = reader.readString(offsets[8]);
  return object;
}

P _localRoutineDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readDateTime(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localRoutineGetId(LocalRoutine object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _localRoutineGetLinks(LocalRoutine object) {
  return [];
}

void _localRoutineAttach(
    IsarCollection<dynamic> col, Id id, LocalRoutine object) {
  object.id = id;
}

extension LocalRoutineByIndex on IsarCollection<LocalRoutine> {
  Future<LocalRoutine?> getByRemoteId(String remoteId) {
    return getByIndex(r'remoteId', [remoteId]);
  }

  LocalRoutine? getByRemoteIdSync(String remoteId) {
    return getByIndexSync(r'remoteId', [remoteId]);
  }

  Future<bool> deleteByRemoteId(String remoteId) {
    return deleteByIndex(r'remoteId', [remoteId]);
  }

  bool deleteByRemoteIdSync(String remoteId) {
    return deleteByIndexSync(r'remoteId', [remoteId]);
  }

  Future<List<LocalRoutine?>> getAllByRemoteId(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'remoteId', values);
  }

  List<LocalRoutine?> getAllByRemoteIdSync(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'remoteId', values);
  }

  Future<int> deleteAllByRemoteId(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'remoteId', values);
  }

  int deleteAllByRemoteIdSync(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'remoteId', values);
  }

  Future<Id> putByRemoteId(LocalRoutine object) {
    return putByIndex(r'remoteId', object);
  }

  Id putByRemoteIdSync(LocalRoutine object, {bool saveLinks = true}) {
    return putByIndexSync(r'remoteId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByRemoteId(List<LocalRoutine> objects) {
    return putAllByIndex(r'remoteId', objects);
  }

  List<Id> putAllByRemoteIdSync(List<LocalRoutine> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'remoteId', objects, saveLinks: saveLinks);
  }
}

extension LocalRoutineQueryWhereSort
    on QueryBuilder<LocalRoutine, LocalRoutine, QWhere> {
  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhere> anyEsDelDia() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'esDelDia'),
      );
    });
  }
}

extension LocalRoutineQueryWhere
    on QueryBuilder<LocalRoutine, LocalRoutine, QWhereClause> {
  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> remoteIdEqualTo(
      String remoteId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'remoteId',
        value: [remoteId],
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause>
      remoteIdNotEqualTo(String remoteId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'remoteId',
              lower: [],
              upper: [remoteId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'remoteId',
              lower: [remoteId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'remoteId',
              lower: [remoteId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'remoteId',
              lower: [],
              upper: [remoteId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> usuarioIdEqualTo(
      String usuarioId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'usuarioId',
        value: [usuarioId],
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause>
      usuarioIdNotEqualTo(String usuarioId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'usuarioId',
              lower: [],
              upper: [usuarioId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'usuarioId',
              lower: [usuarioId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'usuarioId',
              lower: [usuarioId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'usuarioId',
              lower: [],
              upper: [usuarioId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause> esDelDiaEqualTo(
      bool esDelDia) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'esDelDia',
        value: [esDelDia],
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterWhereClause>
      esDelDiaNotEqualTo(bool esDelDia) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'esDelDia',
              lower: [],
              upper: [esDelDia],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'esDelDia',
              lower: [esDelDia],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'esDelDia',
              lower: [esDelDia],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'esDelDia',
              lower: [],
              upper: [esDelDia],
              includeUpper: false,
            ));
      }
    });
  }
}

extension LocalRoutineQueryFilter
    on QueryBuilder<LocalRoutine, LocalRoutine, QFilterCondition> {
  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'completada',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEnIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'completadaEn',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEnIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'completadaEn',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEnEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'completadaEn',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEnGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'completadaEn',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEnLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'completadaEn',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      completadaEnBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'completadaEn',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ejerciciosJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ejerciciosJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ejerciciosJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ejerciciosJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ejerciciosJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ejerciciosJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ejerciciosJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ejerciciosJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ejerciciosJson',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      ejerciciosJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ejerciciosJson',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      esDelDiaEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'esDelDia',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nivelIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'nivel',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nivelIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'nivel',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nivelEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nivel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nivelGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'nivel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nivelLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'nivel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nivelBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'nivel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nivelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'nivel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nivelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'nivel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nivelContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'nivel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nivelMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'nivel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nivelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nivel',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nivelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'nivel',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nombreEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nombre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'nombre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'nombre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nombreBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'nombre',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'nombre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'nombre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'nombre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition> nombreMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'nombre',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nombre',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      nombreIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'nombre',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'remoteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'remoteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'remoteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'remoteId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'remoteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'remoteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'remoteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'remoteId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'remoteId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      remoteIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'remoteId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'usuarioId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'usuarioId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'usuarioId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'usuarioId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'usuarioId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'usuarioId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'usuarioId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'usuarioId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'usuarioId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterFilterCondition>
      usuarioIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'usuarioId',
        value: '',
      ));
    });
  }
}

extension LocalRoutineQueryObject
    on QueryBuilder<LocalRoutine, LocalRoutine, QFilterCondition> {}

extension LocalRoutineQueryLinks
    on QueryBuilder<LocalRoutine, LocalRoutine, QFilterCondition> {}

extension LocalRoutineQuerySortBy
    on QueryBuilder<LocalRoutine, LocalRoutine, QSortBy> {
  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByCompletada() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completada', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      sortByCompletadaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completada', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByCompletadaEn() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completadaEn', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      sortByCompletadaEnDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completadaEn', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      sortByEjerciciosJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ejerciciosJson', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      sortByEjerciciosJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ejerciciosJson', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByEsDelDia() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'esDelDia', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByEsDelDiaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'esDelDia', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByNivel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nivel', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByNivelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nivel', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByNombre() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nombre', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByNombreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nombre', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByRemoteId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByRemoteIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByUsuarioId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usuarioId', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> sortByUsuarioIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usuarioId', Sort.desc);
    });
  }
}

extension LocalRoutineQuerySortThenBy
    on QueryBuilder<LocalRoutine, LocalRoutine, QSortThenBy> {
  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByCompletada() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completada', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      thenByCompletadaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completada', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByCompletadaEn() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completadaEn', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      thenByCompletadaEnDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completadaEn', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      thenByEjerciciosJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ejerciciosJson', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy>
      thenByEjerciciosJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ejerciciosJson', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByEsDelDia() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'esDelDia', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByEsDelDiaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'esDelDia', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByNivel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nivel', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByNivelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nivel', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByNombre() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nombre', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByNombreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nombre', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByRemoteId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByRemoteIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByUsuarioId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usuarioId', Sort.asc);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QAfterSortBy> thenByUsuarioIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usuarioId', Sort.desc);
    });
  }
}

extension LocalRoutineQueryWhereDistinct
    on QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> {
  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByCompletada() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'completada');
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByCompletadaEn() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'completadaEn');
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByEjerciciosJson(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ejerciciosJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByEsDelDia() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'esDelDia');
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByNivel(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nivel', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByNombre(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nombre', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByRemoteId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'remoteId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<LocalRoutine, LocalRoutine, QDistinct> distinctByUsuarioId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'usuarioId', caseSensitive: caseSensitive);
    });
  }
}

extension LocalRoutineQueryProperty
    on QueryBuilder<LocalRoutine, LocalRoutine, QQueryProperty> {
  QueryBuilder<LocalRoutine, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LocalRoutine, bool, QQueryOperations> completadaProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completada');
    });
  }

  QueryBuilder<LocalRoutine, DateTime?, QQueryOperations>
      completadaEnProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completadaEn');
    });
  }

  QueryBuilder<LocalRoutine, String, QQueryOperations>
      ejerciciosJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ejerciciosJson');
    });
  }

  QueryBuilder<LocalRoutine, bool, QQueryOperations> esDelDiaProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'esDelDia');
    });
  }

  QueryBuilder<LocalRoutine, String?, QQueryOperations> nivelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nivel');
    });
  }

  QueryBuilder<LocalRoutine, String, QQueryOperations> nombreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nombre');
    });
  }

  QueryBuilder<LocalRoutine, String, QQueryOperations> remoteIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'remoteId');
    });
  }

  QueryBuilder<LocalRoutine, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<LocalRoutine, String, QQueryOperations> usuarioIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'usuarioId');
    });
  }
}
