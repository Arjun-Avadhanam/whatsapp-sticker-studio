// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $StickersTable extends Stickers with TableInfo<$StickersTable, Sticker> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StickersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<StickerKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StickerKind>($StickersTable.$converterkind);
  static const VerificationMeta _packIdMeta = const VerificationMeta('packId');
  @override
  late final GeneratedColumn<String> packId = GeneratedColumn<String>(
    'pack_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> autoTags =
      GeneratedColumn<String>(
        'auto_tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<String>>($StickersTable.$converterautoTags);
  static const VerificationMeta _manualNameMeta = const VerificationMeta(
    'manualName',
  );
  @override
  late final GeneratedColumn<String> manualName = GeneratedColumn<String>(
    'manual_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> manualTags =
      GeneratedColumn<String>(
        'manual_tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<String>>($StickersTable.$convertermanualTags);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> emojis =
      GeneratedColumn<String>(
        'emojis',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($StickersTable.$converteremojis);
  @override
  late final GeneratedColumnWithTypeConverter<StickerSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StickerSource>($StickersTable.$convertersource);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usageCountMeta = const VerificationMeta(
    'usageCount',
  );
  @override
  late final GeneratedColumn<int> usageCount = GeneratedColumn<int>(
    'usage_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TaggingStatus, String>
  taggingStatus = GeneratedColumn<String>(
    'tagging_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<TaggingStatus>($StickersTable.$convertertaggingStatus);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    filePath,
    thumbnailPath,
    kind,
    packId,
    autoTags,
    manualName,
    manualTags,
    notes,
    emojis,
    source,
    createdAt,
    usageCount,
    sizeBytes,
    taggingStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stickers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sticker> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbnailPathMeta);
    }
    if (data.containsKey('pack_id')) {
      context.handle(
        _packIdMeta,
        packId.isAcceptableOrUnknown(data['pack_id']!, _packIdMeta),
      );
    }
    if (data.containsKey('manual_name')) {
      context.handle(
        _manualNameMeta,
        manualName.isAcceptableOrUnknown(data['manual_name']!, _manualNameMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('usage_count')) {
      context.handle(
        _usageCountMeta,
        usageCount.isAcceptableOrUnknown(data['usage_count']!, _usageCountMeta),
      );
    } else if (isInserting) {
      context.missing(_usageCountMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sticker map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sticker(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      )!,
      kind: $StickersTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      packId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_id'],
      ),
      autoTags: $StickersTable.$converterautoTags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}auto_tags'],
        )!,
      ),
      manualName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manual_name'],
      ),
      manualTags: $StickersTable.$convertermanualTags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}manual_tags'],
        )!,
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      emojis: $StickersTable.$converteremojis.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}emojis'],
        )!,
      ),
      source: $StickersTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      usageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}usage_count'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      taggingStatus: $StickersTable.$convertertaggingStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tagging_status'],
        )!,
      ),
    );
  }

  @override
  $StickersTable createAlias(String alias) {
    return $StickersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<StickerKind, String, String> $converterkind =
      const EnumNameConverter<StickerKind>(StickerKind.values);
  static TypeConverter<List<String>, String> $converterautoTags =
      const StringListConverter();
  static TypeConverter<List<String>, String> $convertermanualTags =
      const StringListConverter();
  static TypeConverter<List<String>, String> $converteremojis =
      const StringListConverter();
  static JsonTypeConverter2<StickerSource, String, String> $convertersource =
      const EnumNameConverter<StickerSource>(StickerSource.values);
  static JsonTypeConverter2<TaggingStatus, String, String>
  $convertertaggingStatus = const EnumNameConverter<TaggingStatus>(
    TaggingStatus.values,
  );
}

class Sticker extends DataClass implements Insertable<Sticker> {
  final String id;
  final String filePath;
  final String thumbnailPath;
  final StickerKind kind;
  final String? packId;
  final List<String> autoTags;
  final String? manualName;
  final List<String> manualTags;
  final String? notes;

  /// Emoji sent to WhatsApp as the sticker's `emojis` field (max 3).
  ///
  /// The only per-sticker signal that helps **inside** WhatsApp: its tray has
  /// its own emoji search, and everything else we index only helps find a
  /// sticker in *our* app. Defaulted rather than nullable so v4 rows read back
  /// as an empty list without a migration backfill.
  final List<String> emojis;
  final StickerSource source;
  final DateTime createdAt;
  final int usageCount;
  final int sizeBytes;
  final TaggingStatus taggingStatus;
  const Sticker({
    required this.id,
    required this.filePath,
    required this.thumbnailPath,
    required this.kind,
    this.packId,
    required this.autoTags,
    this.manualName,
    required this.manualTags,
    this.notes,
    required this.emojis,
    required this.source,
    required this.createdAt,
    required this.usageCount,
    required this.sizeBytes,
    required this.taggingStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['file_path'] = Variable<String>(filePath);
    map['thumbnail_path'] = Variable<String>(thumbnailPath);
    {
      map['kind'] = Variable<String>($StickersTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || packId != null) {
      map['pack_id'] = Variable<String>(packId);
    }
    {
      map['auto_tags'] = Variable<String>(
        $StickersTable.$converterautoTags.toSql(autoTags),
      );
    }
    if (!nullToAbsent || manualName != null) {
      map['manual_name'] = Variable<String>(manualName);
    }
    {
      map['manual_tags'] = Variable<String>(
        $StickersTable.$convertermanualTags.toSql(manualTags),
      );
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    {
      map['emojis'] = Variable<String>(
        $StickersTable.$converteremojis.toSql(emojis),
      );
    }
    {
      map['source'] = Variable<String>(
        $StickersTable.$convertersource.toSql(source),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['usage_count'] = Variable<int>(usageCount);
    map['size_bytes'] = Variable<int>(sizeBytes);
    {
      map['tagging_status'] = Variable<String>(
        $StickersTable.$convertertaggingStatus.toSql(taggingStatus),
      );
    }
    return map;
  }

  StickersCompanion toCompanion(bool nullToAbsent) {
    return StickersCompanion(
      id: Value(id),
      filePath: Value(filePath),
      thumbnailPath: Value(thumbnailPath),
      kind: Value(kind),
      packId: packId == null && nullToAbsent
          ? const Value.absent()
          : Value(packId),
      autoTags: Value(autoTags),
      manualName: manualName == null && nullToAbsent
          ? const Value.absent()
          : Value(manualName),
      manualTags: Value(manualTags),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      emojis: Value(emojis),
      source: Value(source),
      createdAt: Value(createdAt),
      usageCount: Value(usageCount),
      sizeBytes: Value(sizeBytes),
      taggingStatus: Value(taggingStatus),
    );
  }

  factory Sticker.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sticker(
      id: serializer.fromJson<String>(json['id']),
      filePath: serializer.fromJson<String>(json['filePath']),
      thumbnailPath: serializer.fromJson<String>(json['thumbnailPath']),
      kind: $StickersTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      packId: serializer.fromJson<String?>(json['packId']),
      autoTags: serializer.fromJson<List<String>>(json['autoTags']),
      manualName: serializer.fromJson<String?>(json['manualName']),
      manualTags: serializer.fromJson<List<String>>(json['manualTags']),
      notes: serializer.fromJson<String?>(json['notes']),
      emojis: serializer.fromJson<List<String>>(json['emojis']),
      source: $StickersTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      usageCount: serializer.fromJson<int>(json['usageCount']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      taggingStatus: $StickersTable.$convertertaggingStatus.fromJson(
        serializer.fromJson<String>(json['taggingStatus']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'filePath': serializer.toJson<String>(filePath),
      'thumbnailPath': serializer.toJson<String>(thumbnailPath),
      'kind': serializer.toJson<String>(
        $StickersTable.$converterkind.toJson(kind),
      ),
      'packId': serializer.toJson<String?>(packId),
      'autoTags': serializer.toJson<List<String>>(autoTags),
      'manualName': serializer.toJson<String?>(manualName),
      'manualTags': serializer.toJson<List<String>>(manualTags),
      'notes': serializer.toJson<String?>(notes),
      'emojis': serializer.toJson<List<String>>(emojis),
      'source': serializer.toJson<String>(
        $StickersTable.$convertersource.toJson(source),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'usageCount': serializer.toJson<int>(usageCount),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'taggingStatus': serializer.toJson<String>(
        $StickersTable.$convertertaggingStatus.toJson(taggingStatus),
      ),
    };
  }

  Sticker copyWith({
    String? id,
    String? filePath,
    String? thumbnailPath,
    StickerKind? kind,
    Value<String?> packId = const Value.absent(),
    List<String>? autoTags,
    Value<String?> manualName = const Value.absent(),
    List<String>? manualTags,
    Value<String?> notes = const Value.absent(),
    List<String>? emojis,
    StickerSource? source,
    DateTime? createdAt,
    int? usageCount,
    int? sizeBytes,
    TaggingStatus? taggingStatus,
  }) => Sticker(
    id: id ?? this.id,
    filePath: filePath ?? this.filePath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    kind: kind ?? this.kind,
    packId: packId.present ? packId.value : this.packId,
    autoTags: autoTags ?? this.autoTags,
    manualName: manualName.present ? manualName.value : this.manualName,
    manualTags: manualTags ?? this.manualTags,
    notes: notes.present ? notes.value : this.notes,
    emojis: emojis ?? this.emojis,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    usageCount: usageCount ?? this.usageCount,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    taggingStatus: taggingStatus ?? this.taggingStatus,
  );
  Sticker copyWithCompanion(StickersCompanion data) {
    return Sticker(
      id: data.id.present ? data.id.value : this.id,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      kind: data.kind.present ? data.kind.value : this.kind,
      packId: data.packId.present ? data.packId.value : this.packId,
      autoTags: data.autoTags.present ? data.autoTags.value : this.autoTags,
      manualName: data.manualName.present
          ? data.manualName.value
          : this.manualName,
      manualTags: data.manualTags.present
          ? data.manualTags.value
          : this.manualTags,
      notes: data.notes.present ? data.notes.value : this.notes,
      emojis: data.emojis.present ? data.emojis.value : this.emojis,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      usageCount: data.usageCount.present
          ? data.usageCount.value
          : this.usageCount,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      taggingStatus: data.taggingStatus.present
          ? data.taggingStatus.value
          : this.taggingStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sticker(')
          ..write('id: $id, ')
          ..write('filePath: $filePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('kind: $kind, ')
          ..write('packId: $packId, ')
          ..write('autoTags: $autoTags, ')
          ..write('manualName: $manualName, ')
          ..write('manualTags: $manualTags, ')
          ..write('notes: $notes, ')
          ..write('emojis: $emojis, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('usageCount: $usageCount, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('taggingStatus: $taggingStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    filePath,
    thumbnailPath,
    kind,
    packId,
    autoTags,
    manualName,
    manualTags,
    notes,
    emojis,
    source,
    createdAt,
    usageCount,
    sizeBytes,
    taggingStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sticker &&
          other.id == this.id &&
          other.filePath == this.filePath &&
          other.thumbnailPath == this.thumbnailPath &&
          other.kind == this.kind &&
          other.packId == this.packId &&
          other.autoTags == this.autoTags &&
          other.manualName == this.manualName &&
          other.manualTags == this.manualTags &&
          other.notes == this.notes &&
          other.emojis == this.emojis &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.usageCount == this.usageCount &&
          other.sizeBytes == this.sizeBytes &&
          other.taggingStatus == this.taggingStatus);
}

class StickersCompanion extends UpdateCompanion<Sticker> {
  final Value<String> id;
  final Value<String> filePath;
  final Value<String> thumbnailPath;
  final Value<StickerKind> kind;
  final Value<String?> packId;
  final Value<List<String>> autoTags;
  final Value<String?> manualName;
  final Value<List<String>> manualTags;
  final Value<String?> notes;
  final Value<List<String>> emojis;
  final Value<StickerSource> source;
  final Value<DateTime> createdAt;
  final Value<int> usageCount;
  final Value<int> sizeBytes;
  final Value<TaggingStatus> taggingStatus;
  final Value<int> rowid;
  const StickersCompanion({
    this.id = const Value.absent(),
    this.filePath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.kind = const Value.absent(),
    this.packId = const Value.absent(),
    this.autoTags = const Value.absent(),
    this.manualName = const Value.absent(),
    this.manualTags = const Value.absent(),
    this.notes = const Value.absent(),
    this.emojis = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.usageCount = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.taggingStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StickersCompanion.insert({
    required String id,
    required String filePath,
    required String thumbnailPath,
    required StickerKind kind,
    this.packId = const Value.absent(),
    required List<String> autoTags,
    this.manualName = const Value.absent(),
    required List<String> manualTags,
    this.notes = const Value.absent(),
    this.emojis = const Value.absent(),
    required StickerSource source,
    required DateTime createdAt,
    required int usageCount,
    required int sizeBytes,
    required TaggingStatus taggingStatus,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       filePath = Value(filePath),
       thumbnailPath = Value(thumbnailPath),
       kind = Value(kind),
       autoTags = Value(autoTags),
       manualTags = Value(manualTags),
       source = Value(source),
       createdAt = Value(createdAt),
       usageCount = Value(usageCount),
       sizeBytes = Value(sizeBytes),
       taggingStatus = Value(taggingStatus);
  static Insertable<Sticker> custom({
    Expression<String>? id,
    Expression<String>? filePath,
    Expression<String>? thumbnailPath,
    Expression<String>? kind,
    Expression<String>? packId,
    Expression<String>? autoTags,
    Expression<String>? manualName,
    Expression<String>? manualTags,
    Expression<String>? notes,
    Expression<String>? emojis,
    Expression<String>? source,
    Expression<DateTime>? createdAt,
    Expression<int>? usageCount,
    Expression<int>? sizeBytes,
    Expression<String>? taggingStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filePath != null) 'file_path': filePath,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (kind != null) 'kind': kind,
      if (packId != null) 'pack_id': packId,
      if (autoTags != null) 'auto_tags': autoTags,
      if (manualName != null) 'manual_name': manualName,
      if (manualTags != null) 'manual_tags': manualTags,
      if (notes != null) 'notes': notes,
      if (emojis != null) 'emojis': emojis,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (usageCount != null) 'usage_count': usageCount,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (taggingStatus != null) 'tagging_status': taggingStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StickersCompanion copyWith({
    Value<String>? id,
    Value<String>? filePath,
    Value<String>? thumbnailPath,
    Value<StickerKind>? kind,
    Value<String?>? packId,
    Value<List<String>>? autoTags,
    Value<String?>? manualName,
    Value<List<String>>? manualTags,
    Value<String?>? notes,
    Value<List<String>>? emojis,
    Value<StickerSource>? source,
    Value<DateTime>? createdAt,
    Value<int>? usageCount,
    Value<int>? sizeBytes,
    Value<TaggingStatus>? taggingStatus,
    Value<int>? rowid,
  }) {
    return StickersCompanion(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      kind: kind ?? this.kind,
      packId: packId ?? this.packId,
      autoTags: autoTags ?? this.autoTags,
      manualName: manualName ?? this.manualName,
      manualTags: manualTags ?? this.manualTags,
      notes: notes ?? this.notes,
      emojis: emojis ?? this.emojis,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      usageCount: usageCount ?? this.usageCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      taggingStatus: taggingStatus ?? this.taggingStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $StickersTable.$converterkind.toSql(kind.value),
      );
    }
    if (packId.present) {
      map['pack_id'] = Variable<String>(packId.value);
    }
    if (autoTags.present) {
      map['auto_tags'] = Variable<String>(
        $StickersTable.$converterautoTags.toSql(autoTags.value),
      );
    }
    if (manualName.present) {
      map['manual_name'] = Variable<String>(manualName.value);
    }
    if (manualTags.present) {
      map['manual_tags'] = Variable<String>(
        $StickersTable.$convertermanualTags.toSql(manualTags.value),
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (emojis.present) {
      map['emojis'] = Variable<String>(
        $StickersTable.$converteremojis.toSql(emojis.value),
      );
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $StickersTable.$convertersource.toSql(source.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (usageCount.present) {
      map['usage_count'] = Variable<int>(usageCount.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (taggingStatus.present) {
      map['tagging_status'] = Variable<String>(
        $StickersTable.$convertertaggingStatus.toSql(taggingStatus.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StickersCompanion(')
          ..write('id: $id, ')
          ..write('filePath: $filePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('kind: $kind, ')
          ..write('packId: $packId, ')
          ..write('autoTags: $autoTags, ')
          ..write('manualName: $manualName, ')
          ..write('manualTags: $manualTags, ')
          ..write('notes: $notes, ')
          ..write('emojis: $emojis, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('usageCount: $usageCount, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('taggingStatus: $taggingStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PacksTable extends Packs with TableInfo<$PacksTable, Pack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trayIconPathMeta = const VerificationMeta(
    'trayIconPath',
  );
  @override
  late final GeneratedColumn<String> trayIconPath = GeneratedColumn<String>(
    'tray_icon_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isAnimatedMeta = const VerificationMeta(
    'isAnimated',
  );
  @override
  late final GeneratedColumn<bool> isAnimated = GeneratedColumn<bool>(
    'is_animated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_animated" IN (0, 1))',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> stickerIds =
      GeneratedColumn<String>(
        'sticker_ids',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<String>>($PacksTable.$converterstickerIds);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    trayIconPath,
    isAnimated,
    stickerIds,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'packs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Pack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('tray_icon_path')) {
      context.handle(
        _trayIconPathMeta,
        trayIconPath.isAcceptableOrUnknown(
          data['tray_icon_path']!,
          _trayIconPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trayIconPathMeta);
    }
    if (data.containsKey('is_animated')) {
      context.handle(
        _isAnimatedMeta,
        isAnimated.isAcceptableOrUnknown(data['is_animated']!, _isAnimatedMeta),
      );
    } else if (isInserting) {
      context.missing(_isAnimatedMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Pack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pack(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      trayIconPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tray_icon_path'],
      )!,
      isAnimated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_animated'],
      )!,
      stickerIds: $PacksTable.$converterstickerIds.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sticker_ids'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PacksTable createAlias(String alias) {
    return $PacksTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterstickerIds =
      const StringListConverter();
}

class Pack extends DataClass implements Insertable<Pack> {
  final String id;
  final String name;
  final String trayIconPath;
  final bool isAnimated;
  final List<String> stickerIds;
  final DateTime createdAt;
  const Pack({
    required this.id,
    required this.name,
    required this.trayIconPath,
    required this.isAnimated,
    required this.stickerIds,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['tray_icon_path'] = Variable<String>(trayIconPath);
    map['is_animated'] = Variable<bool>(isAnimated);
    {
      map['sticker_ids'] = Variable<String>(
        $PacksTable.$converterstickerIds.toSql(stickerIds),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PacksCompanion toCompanion(bool nullToAbsent) {
    return PacksCompanion(
      id: Value(id),
      name: Value(name),
      trayIconPath: Value(trayIconPath),
      isAnimated: Value(isAnimated),
      stickerIds: Value(stickerIds),
      createdAt: Value(createdAt),
    );
  }

  factory Pack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pack(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      trayIconPath: serializer.fromJson<String>(json['trayIconPath']),
      isAnimated: serializer.fromJson<bool>(json['isAnimated']),
      stickerIds: serializer.fromJson<List<String>>(json['stickerIds']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'trayIconPath': serializer.toJson<String>(trayIconPath),
      'isAnimated': serializer.toJson<bool>(isAnimated),
      'stickerIds': serializer.toJson<List<String>>(stickerIds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Pack copyWith({
    String? id,
    String? name,
    String? trayIconPath,
    bool? isAnimated,
    List<String>? stickerIds,
    DateTime? createdAt,
  }) => Pack(
    id: id ?? this.id,
    name: name ?? this.name,
    trayIconPath: trayIconPath ?? this.trayIconPath,
    isAnimated: isAnimated ?? this.isAnimated,
    stickerIds: stickerIds ?? this.stickerIds,
    createdAt: createdAt ?? this.createdAt,
  );
  Pack copyWithCompanion(PacksCompanion data) {
    return Pack(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      trayIconPath: data.trayIconPath.present
          ? data.trayIconPath.value
          : this.trayIconPath,
      isAnimated: data.isAnimated.present
          ? data.isAnimated.value
          : this.isAnimated,
      stickerIds: data.stickerIds.present
          ? data.stickerIds.value
          : this.stickerIds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pack(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('trayIconPath: $trayIconPath, ')
          ..write('isAnimated: $isAnimated, ')
          ..write('stickerIds: $stickerIds, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, trayIconPath, isAnimated, stickerIds, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pack &&
          other.id == this.id &&
          other.name == this.name &&
          other.trayIconPath == this.trayIconPath &&
          other.isAnimated == this.isAnimated &&
          other.stickerIds == this.stickerIds &&
          other.createdAt == this.createdAt);
}

class PacksCompanion extends UpdateCompanion<Pack> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> trayIconPath;
  final Value<bool> isAnimated;
  final Value<List<String>> stickerIds;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PacksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.trayIconPath = const Value.absent(),
    this.isAnimated = const Value.absent(),
    this.stickerIds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PacksCompanion.insert({
    required String id,
    required String name,
    required String trayIconPath,
    required bool isAnimated,
    required List<String> stickerIds,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       trayIconPath = Value(trayIconPath),
       isAnimated = Value(isAnimated),
       stickerIds = Value(stickerIds),
       createdAt = Value(createdAt);
  static Insertable<Pack> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? trayIconPath,
    Expression<bool>? isAnimated,
    Expression<String>? stickerIds,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (trayIconPath != null) 'tray_icon_path': trayIconPath,
      if (isAnimated != null) 'is_animated': isAnimated,
      if (stickerIds != null) 'sticker_ids': stickerIds,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PacksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? trayIconPath,
    Value<bool>? isAnimated,
    Value<List<String>>? stickerIds,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PacksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      trayIconPath: trayIconPath ?? this.trayIconPath,
      isAnimated: isAnimated ?? this.isAnimated,
      stickerIds: stickerIds ?? this.stickerIds,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (trayIconPath.present) {
      map['tray_icon_path'] = Variable<String>(trayIconPath.value);
    }
    if (isAnimated.present) {
      map['is_animated'] = Variable<bool>(isAnimated.value);
    }
    if (stickerIds.present) {
      map['sticker_ids'] = Variable<String>(
        $PacksTable.$converterstickerIds.toSql(stickerIds.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PacksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('trayIconPath: $trayIconPath, ')
          ..write('isAnimated: $isAnimated, ')
          ..write('stickerIds: $stickerIds, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $StickersTable stickers = $StickersTable(this);
  late final $PacksTable packs = $PacksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [stickers, packs];
}

typedef $$StickersTableCreateCompanionBuilder =
    StickersCompanion Function({
      required String id,
      required String filePath,
      required String thumbnailPath,
      required StickerKind kind,
      Value<String?> packId,
      required List<String> autoTags,
      Value<String?> manualName,
      required List<String> manualTags,
      Value<String?> notes,
      Value<List<String>> emojis,
      required StickerSource source,
      required DateTime createdAt,
      required int usageCount,
      required int sizeBytes,
      required TaggingStatus taggingStatus,
      Value<int> rowid,
    });
typedef $$StickersTableUpdateCompanionBuilder =
    StickersCompanion Function({
      Value<String> id,
      Value<String> filePath,
      Value<String> thumbnailPath,
      Value<StickerKind> kind,
      Value<String?> packId,
      Value<List<String>> autoTags,
      Value<String?> manualName,
      Value<List<String>> manualTags,
      Value<String?> notes,
      Value<List<String>> emojis,
      Value<StickerSource> source,
      Value<DateTime> createdAt,
      Value<int> usageCount,
      Value<int> sizeBytes,
      Value<TaggingStatus> taggingStatus,
      Value<int> rowid,
    });

class $$StickersTableFilterComposer
    extends Composer<_$AppDatabase, $StickersTable> {
  $$StickersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<StickerKind, StickerKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get packId => $composableBuilder(
    column: $table.packId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get autoTags => $composableBuilder(
    column: $table.autoTags,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get manualName => $composableBuilder(
    column: $table.manualName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get manualTags => $composableBuilder(
    column: $table.manualTags,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get emojis => $composableBuilder(
    column: $table.emojis,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<StickerSource, StickerSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usageCount => $composableBuilder(
    column: $table.usageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TaggingStatus, TaggingStatus, String>
  get taggingStatus => $composableBuilder(
    column: $table.taggingStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$StickersTableOrderingComposer
    extends Composer<_$AppDatabase, $StickersTable> {
  $$StickersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packId => $composableBuilder(
    column: $table.packId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoTags => $composableBuilder(
    column: $table.autoTags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualName => $composableBuilder(
    column: $table.manualName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualTags => $composableBuilder(
    column: $table.manualTags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emojis => $composableBuilder(
    column: $table.emojis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usageCount => $composableBuilder(
    column: $table.usageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taggingStatus => $composableBuilder(
    column: $table.taggingStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StickersTableAnnotationComposer
    extends Composer<_$AppDatabase, $StickersTable> {
  $$StickersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<StickerKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get packId =>
      $composableBuilder(column: $table.packId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get autoTags =>
      $composableBuilder(column: $table.autoTags, builder: (column) => column);

  GeneratedColumn<String> get manualName => $composableBuilder(
    column: $table.manualName,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get manualTags =>
      $composableBuilder(
        column: $table.manualTags,
        builder: (column) => column,
      );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get emojis =>
      $composableBuilder(column: $table.emojis, builder: (column) => column);

  GeneratedColumnWithTypeConverter<StickerSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get usageCount => $composableBuilder(
    column: $table.usageCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaggingStatus, String> get taggingStatus =>
      $composableBuilder(
        column: $table.taggingStatus,
        builder: (column) => column,
      );
}

class $$StickersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StickersTable,
          Sticker,
          $$StickersTableFilterComposer,
          $$StickersTableOrderingComposer,
          $$StickersTableAnnotationComposer,
          $$StickersTableCreateCompanionBuilder,
          $$StickersTableUpdateCompanionBuilder,
          (Sticker, BaseReferences<_$AppDatabase, $StickersTable, Sticker>),
          Sticker,
          PrefetchHooks Function()
        > {
  $$StickersTableTableManager(_$AppDatabase db, $StickersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StickersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StickersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StickersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> thumbnailPath = const Value.absent(),
                Value<StickerKind> kind = const Value.absent(),
                Value<String?> packId = const Value.absent(),
                Value<List<String>> autoTags = const Value.absent(),
                Value<String?> manualName = const Value.absent(),
                Value<List<String>> manualTags = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<List<String>> emojis = const Value.absent(),
                Value<StickerSource> source = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> usageCount = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<TaggingStatus> taggingStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StickersCompanion(
                id: id,
                filePath: filePath,
                thumbnailPath: thumbnailPath,
                kind: kind,
                packId: packId,
                autoTags: autoTags,
                manualName: manualName,
                manualTags: manualTags,
                notes: notes,
                emojis: emojis,
                source: source,
                createdAt: createdAt,
                usageCount: usageCount,
                sizeBytes: sizeBytes,
                taggingStatus: taggingStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String filePath,
                required String thumbnailPath,
                required StickerKind kind,
                Value<String?> packId = const Value.absent(),
                required List<String> autoTags,
                Value<String?> manualName = const Value.absent(),
                required List<String> manualTags,
                Value<String?> notes = const Value.absent(),
                Value<List<String>> emojis = const Value.absent(),
                required StickerSource source,
                required DateTime createdAt,
                required int usageCount,
                required int sizeBytes,
                required TaggingStatus taggingStatus,
                Value<int> rowid = const Value.absent(),
              }) => StickersCompanion.insert(
                id: id,
                filePath: filePath,
                thumbnailPath: thumbnailPath,
                kind: kind,
                packId: packId,
                autoTags: autoTags,
                manualName: manualName,
                manualTags: manualTags,
                notes: notes,
                emojis: emojis,
                source: source,
                createdAt: createdAt,
                usageCount: usageCount,
                sizeBytes: sizeBytes,
                taggingStatus: taggingStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StickersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StickersTable,
      Sticker,
      $$StickersTableFilterComposer,
      $$StickersTableOrderingComposer,
      $$StickersTableAnnotationComposer,
      $$StickersTableCreateCompanionBuilder,
      $$StickersTableUpdateCompanionBuilder,
      (Sticker, BaseReferences<_$AppDatabase, $StickersTable, Sticker>),
      Sticker,
      PrefetchHooks Function()
    >;
typedef $$PacksTableCreateCompanionBuilder =
    PacksCompanion Function({
      required String id,
      required String name,
      required String trayIconPath,
      required bool isAnimated,
      required List<String> stickerIds,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$PacksTableUpdateCompanionBuilder =
    PacksCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> trayIconPath,
      Value<bool> isAnimated,
      Value<List<String>> stickerIds,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PacksTableFilterComposer extends Composer<_$AppDatabase, $PacksTable> {
  $$PacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trayIconPath => $composableBuilder(
    column: $table.trayIconPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAnimated => $composableBuilder(
    column: $table.isAnimated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get stickerIds => $composableBuilder(
    column: $table.stickerIds,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PacksTableOrderingComposer
    extends Composer<_$AppDatabase, $PacksTable> {
  $$PacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trayIconPath => $composableBuilder(
    column: $table.trayIconPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAnimated => $composableBuilder(
    column: $table.isAnimated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stickerIds => $composableBuilder(
    column: $table.stickerIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PacksTableAnnotationComposer
    extends Composer<_$AppDatabase, $PacksTable> {
  $$PacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get trayIconPath => $composableBuilder(
    column: $table.trayIconPath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isAnimated => $composableBuilder(
    column: $table.isAnimated,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get stickerIds =>
      $composableBuilder(
        column: $table.stickerIds,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PacksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PacksTable,
          Pack,
          $$PacksTableFilterComposer,
          $$PacksTableOrderingComposer,
          $$PacksTableAnnotationComposer,
          $$PacksTableCreateCompanionBuilder,
          $$PacksTableUpdateCompanionBuilder,
          (Pack, BaseReferences<_$AppDatabase, $PacksTable, Pack>),
          Pack,
          PrefetchHooks Function()
        > {
  $$PacksTableTableManager(_$AppDatabase db, $PacksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PacksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> trayIconPath = const Value.absent(),
                Value<bool> isAnimated = const Value.absent(),
                Value<List<String>> stickerIds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PacksCompanion(
                id: id,
                name: name,
                trayIconPath: trayIconPath,
                isAnimated: isAnimated,
                stickerIds: stickerIds,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String trayIconPath,
                required bool isAnimated,
                required List<String> stickerIds,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PacksCompanion.insert(
                id: id,
                name: name,
                trayIconPath: trayIconPath,
                isAnimated: isAnimated,
                stickerIds: stickerIds,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PacksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PacksTable,
      Pack,
      $$PacksTableFilterComposer,
      $$PacksTableOrderingComposer,
      $$PacksTableAnnotationComposer,
      $$PacksTableCreateCompanionBuilder,
      $$PacksTableUpdateCompanionBuilder,
      (Pack, BaseReferences<_$AppDatabase, $PacksTable, Pack>),
      Pack,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$StickersTableTableManager get stickers =>
      $$StickersTableTableManager(_db, _db.stickers);
  $$PacksTableTableManager get packs =>
      $$PacksTableTableManager(_db, _db.packs);
}
