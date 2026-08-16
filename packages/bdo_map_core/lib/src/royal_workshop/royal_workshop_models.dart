enum BdoRoyalWorkshopKind { production, processing }

const int bdoRoyalWorkshopAccessContributionPoints = 5;

class BdoRoyalWorkshopArea {
  const BdoRoyalWorkshopArea({
    required this.id,
    required this.name,
    required this.kind,
    required this.managerName,
    required this.managerNpcId,
    required this.managerWorldX,
    required this.managerWorldZ,
    required this.workshops,
    required this.mapX,
    required this.mapY,
  });

  final String id;
  final String name;
  final BdoRoyalWorkshopKind kind;
  final String managerName;
  final int managerNpcId;
  final double managerWorldX;
  final double managerWorldZ;
  final List<BdoRoyalWorkshopDefinition> workshops;
  final double mapX;
  final double mapY;

  int get maximumWorkshops => workshops.length;

  BdoRoyalWorkshopDefinition workshopAt(int index) =>
      workshops[index.clamp(0, workshops.length - 1)];
}

class BdoRoyalWorkshopDefinition {
  const BdoRoyalWorkshopDefinition({
    required this.name,
    required this.morningGratitudeTokenCost,
  });

  final String name;
  final int morningGratitudeTokenCost;

  bool get isStartingWorkshop => morningGratitudeTokenCost == 0;
}

const List<BdoRoyalWorkshopArea> bdoRoyalWorkshopAreas = <BdoRoyalWorkshopArea>[
  BdoRoyalWorkshopArea(
    id: 'gyeonghoeru',
    name: 'Gyeonghoeru Pavilion',
    kind: BdoRoyalWorkshopKind.production,
    managerName: 'Yeongman',
    managerNpcId: 62114,
    managerWorldX: -1399270,
    managerWorldZ: 1344970,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Hamhong Gate',
        morningGratitudeTokenCost: 500,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Igyeon Gate',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Hahyangjeong Pavilion',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Mansesan',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .26,
    mapY: .18,
  ),
  BdoRoyalWorkshopArea(
    id: 'palace-kitchen',
    name: 'Palace Kitchen',
    kind: BdoRoyalWorkshopKind.processing,
    managerName: 'Park Sugyeong',
    managerNpcId: 62120,
    managerWorldX: -1402340,
    managerWorldZ: 1314530,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Inner Palace Kitchen',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Outer Palace Kitchen',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .57,
    mapY: .18,
  ),
  BdoRoyalWorkshopArea(
    id: 'infirmary',
    name: 'Infirmary',
    kind: BdoRoyalWorkshopKind.production,
    managerName: 'Choi Doyun',
    managerNpcId: 62115,
    managerWorldX: -1419340,
    managerWorldZ: 1273640,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Byeoljwa',
        morningGratitudeTokenCost: 500,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Hundo',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Bujeong',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Noksa',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .82,
    mapY: .32,
  ),
  BdoRoyalWorkshopArea(
    id: 'military',
    name: 'Military',
    kind: BdoRoyalWorkshopKind.processing,
    managerName: 'Hyeokcheol',
    managerNpcId: 62125,
    managerWorldX: -1428400,
    managerWorldZ: 1349790,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Armory',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Central Command HQ',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .28,
    mapY: .48,
  ),
  BdoRoyalWorkshopArea(
    id: 'seonwonjeon',
    name: 'Seonwonjeon Hall',
    kind: BdoRoyalWorkshopKind.processing,
    managerName: 'Sangdeok',
    managerNpcId: 62121,
    managerWorldX: -1423780,
    managerWorldZ: 1314320,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Inner Chamber',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Gyeongan Hall',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .58,
    mapY: .43,
  ),
  BdoRoyalWorkshopArea(
    id: 'libraries',
    name: 'History of Libraries',
    kind: BdoRoyalWorkshopKind.processing,
    managerName: 'Seokdo',
    managerNpcId: 62123,
    managerWorldX: -1438140,
    managerWorldZ: 1313410,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Gyujanggak Library',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Government Records Office',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .62,
    mapY: .64,
  ),
  BdoRoyalWorkshopArea(
    id: 'leftward-office',
    name: 'Leftward Office',
    kind: BdoRoyalWorkshopKind.production,
    managerName: 'Kim Munki',
    managerNpcId: 62116,
    managerWorldX: -1458930,
    managerWorldZ: 1344580,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Ministry of Law',
        morningGratitudeTokenCost: 500,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Ministry of Works',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Training Institute',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Armaments Office',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .31,
    mapY: .84,
  ),
  BdoRoyalWorkshopArea(
    id: 'rightward-office',
    name: 'Rightward Office',
    kind: BdoRoyalWorkshopKind.production,
    managerName: 'Park Gyusik',
    managerNpcId: 62117,
    managerWorldX: -1471920,
    managerWorldZ: 1330250,
    workshops: <BdoRoyalWorkshopDefinition>[
      BdoRoyalWorkshopDefinition(
        name: 'Basic workshop',
        morningGratitudeTokenCost: 0,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Ministry of Treasury',
        morningGratitudeTokenCost: 500,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Land Management Office',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Civil Appointments Office',
        morningGratitudeTokenCost: 1000,
      ),
      BdoRoyalWorkshopDefinition(
        name: 'Staffing Office',
        morningGratitudeTokenCost: 1000,
      ),
    ],
    mapX: .57,
    mapY: .84,
  ),
];

final Map<String, BdoRoyalWorkshopArea> bdoRoyalWorkshopAreasById =
    <String, BdoRoyalWorkshopArea>{
      for (final area in bdoRoyalWorkshopAreas) area.id: area,
    };

class BdoRoyalWorkshopGood {
  const BdoRoyalWorkshopGood({
    required this.id,
    required this.name,
    required this.kind,
    required this.referencePrice,
    required this.rareRoll,
    this.durationAt150WorkerSpeedHours,
  });

  final int id;
  final String name;
  final BdoRoyalWorkshopKind kind;

  /// Client metadata only. It is never used as guaranteed profit.
  final int referencePrice;
  final bool rareRoll;
  final double? durationAt150WorkerSpeedHours;

  factory BdoRoyalWorkshopGood.fromJson(Map<Object?, Object?> json) {
    final rawKind = '${json['kind']}';
    return BdoRoyalWorkshopGood(
      id: (json['id'] as num).toInt(),
      name: '${json['name']}'.trim(),
      kind: rawKind == 'processing'
          ? BdoRoyalWorkshopKind.processing
          : BdoRoyalWorkshopKind.production,
      referencePrice: (json['referencePrice'] as num?)?.toInt() ?? 0,
      rareRoll: json['rareRoll'] == true,
      durationAt150WorkerSpeedHours:
          (json['durationAt150WorkerSpeedHours'] as num?)?.toDouble(),
    );
  }
}

class BdoRoyalWorkshopSlotPlan {
  const BdoRoyalWorkshopSlotPlan({
    this.selectedGoodId,
    this.recordedGoodName = '',
    this.workerName = '',
    this.taskHours,
    this.repeatCount = 1,
    this.netSilverPerCycle,
    this.isRareOrSpecial = false,
    this.isRunning = false,
  });

  final int? selectedGoodId;

  /// The exact roll or recipe copied from the in-game workshop.
  ///
  /// The app intentionally does not infer which goods are eligible for an
  /// area or slot because a trustworthy eligibility table is not available.
  final String recordedGoodName;
  final String workerName;
  final double? taskHours;
  final int repeatCount;

  /// Player-entered ordinary net value for the recorded task.
  ///
  /// Rare or special rolls are deliberately excluded by the evaluator.
  final double? netSilverPerCycle;
  final bool isRareOrSpecial;
  final bool isRunning;

  bool get hasRecordedGood =>
      selectedGoodId != null || recordedGoodName.trim().isNotEmpty;
  bool get hasWorker => workerName.trim().isNotEmpty;
  bool get hasTimedTask => taskHours != null && taskHours! > 0;

  BdoRoyalWorkshopSlotPlan copyWith({
    int? selectedGoodId,
    bool clearSelectedGood = false,
    String? recordedGoodName,
    String? workerName,
    bool clearWorkerName = false,
    double? taskHours,
    bool clearTaskHours = false,
    int? repeatCount,
    double? netSilverPerCycle,
    bool clearNetSilverPerCycle = false,
    bool? isRareOrSpecial,
    bool? isRunning,
  }) {
    return BdoRoyalWorkshopSlotPlan(
      selectedGoodId: clearSelectedGood
          ? null
          : selectedGoodId ?? this.selectedGoodId,
      recordedGoodName: recordedGoodName ?? this.recordedGoodName,
      workerName: clearWorkerName ? '' : workerName ?? this.workerName,
      taskHours: clearTaskHours ? null : taskHours ?? this.taskHours,
      repeatCount: repeatCount ?? this.repeatCount,
      netSilverPerCycle: clearNetSilverPerCycle
          ? null
          : netSilverPerCycle ?? this.netSilverPerCycle,
      isRareOrSpecial: isRareOrSpecial ?? this.isRareOrSpecial,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'selectedGoodId': ?selectedGoodId,
    if (recordedGoodName.trim().isNotEmpty)
      'recordedGoodName': recordedGoodName.trim(),
    if (workerName.trim().isNotEmpty) 'workerName': workerName.trim(),
    'taskHours': ?taskHours,
    'repeatCount': repeatCount,
    'netSilverPerCycle': ?netSilverPerCycle,
    if (isRareOrSpecial) 'isRareOrSpecial': true,
    if (isRunning) 'isRunning': true,
  };

  factory BdoRoyalWorkshopSlotPlan.fromJson(Object? json) {
    if (json is! Map) return const BdoRoyalWorkshopSlotPlan();
    return BdoRoyalWorkshopSlotPlan(
      selectedGoodId: _positiveInt(json['selectedGoodId']),
      recordedGoodName: '${json['recordedGoodName'] ?? ''}'.trim(),
      workerName: '${json['workerName'] ?? ''}'.trim(),
      taskHours: _positiveDouble(json['taskHours']),
      repeatCount: _positiveInt(json['repeatCount']) ?? 1,
      netSilverPerCycle: _nonNegativeDouble(json['netSilverPerCycle']),
      isRareOrSpecial: json['isRareOrSpecial'] == true,
      isRunning: json['isRunning'] == true,
    );
  }

  bool sameValuesAs(BdoRoyalWorkshopSlotPlan other) =>
      selectedGoodId == other.selectedGoodId &&
      recordedGoodName == other.recordedGoodName &&
      workerName == other.workerName &&
      taskHours == other.taskHours &&
      repeatCount == other.repeatCount &&
      netSilverPerCycle == other.netSilverPerCycle &&
      isRareOrSpecial == other.isRareOrSpecial &&
      isRunning == other.isRunning;

  bool sameTaskValuesAs(BdoRoyalWorkshopSlotPlan other) =>
      selectedGoodId == other.selectedGoodId &&
      recordedGoodName == other.recordedGoodName &&
      taskHours == other.taskHours &&
      repeatCount == other.repeatCount &&
      netSilverPerCycle == other.netSilverPerCycle &&
      isRareOrSpecial == other.isRareOrSpecial;
}

class BdoRoyalWorkshopAreaPlan {
  const BdoRoyalWorkshopAreaPlan({
    int unlockedWorkshopCount = 1,
    this.unlockedWorkshopIndices = const <int>{},
    this.activeWorkshopIndex = 0,
    this.workerName = '',
    this.isRunning = false,
    this.workshopPlans = const <int, BdoRoyalWorkshopSlotPlan>{},
  }) : legacyUnlockedWorkshopCount = unlockedWorkshopCount;

  /// Prefix count from the older schema. New saves use
  /// [unlockedWorkshopIndices] so named workshops can be recorded
  /// independently, as they are in the in-game manager list.
  final int legacyUnlockedWorkshopCount;
  final Set<int> unlockedWorkshopIndices;
  final int activeWorkshopIndex;

  /// One Yukjo worker is assigned to the palace area, not to every workshop.
  final String workerName;

  /// Only the selected workshop in this area can be running.
  final bool isRunning;
  final Map<int, BdoRoyalWorkshopSlotPlan> workshopPlans;

  Set<int> get unlockedIndices {
    if (unlockedWorkshopIndices.isNotEmpty) {
      return <int>{0, ...unlockedWorkshopIndices.where((index) => index >= 0)};
    }
    final count = legacyUnlockedWorkshopCount < 1
        ? 1
        : legacyUnlockedWorkshopCount;
    return <int>{for (var index = 0; index < count; index++) index};
  }

  int get unlockedWorkshopCount => unlockedIndices.length;

  bool isWorkshopUnlocked(int workshopIndex) =>
      unlockedIndices.contains(workshopIndex);

  int get normalizedActiveWorkshopIndex {
    final unlocked = unlockedIndices.toList()..sort();
    if (unlocked.contains(activeWorkshopIndex)) {
      return activeWorkshopIndex;
    }
    return unlocked.first;
  }

  Iterable<MapEntry<int, BdoRoyalWorkshopSlotPlan>> get unlockedWorkshopPlans =>
      workshopPlans.entries.where((entry) => isWorkshopUnlocked(entry.key));

  BdoRoyalWorkshopSlotPlan planFor(int workshopIndex) =>
      workshopPlans[workshopIndex] ?? const BdoRoyalWorkshopSlotPlan();

  BdoRoyalWorkshopSlotPlan get activePlan =>
      planFor(normalizedActiveWorkshopIndex);

  /// Runtime values stored by the incorrect per-workshop schema are accepted
  /// until the plan is next changed, so existing user data remains useful.
  String get effectiveWorkerName {
    final current = workerName.trim();
    if (current.isNotEmpty) return current;
    final legacyCurrent = activePlan.workerName.trim();
    if (legacyCurrent.isNotEmpty) return legacyCurrent;
    for (final entry in unlockedWorkshopPlans) {
      final legacy = entry.value.workerName.trim();
      if (legacy.isNotEmpty) return legacy;
    }
    return '';
  }

  bool get effectiveIsRunning => isRunning || activePlan.isRunning;

  BdoRoyalWorkshopAreaPlan copyWith({
    int? unlockedWorkshopCount,
    Set<int>? unlockedWorkshopIndices,
    int? activeWorkshopIndex,
    String? workerName,
    bool clearWorkerName = false,
    bool? isRunning,
    Map<int, BdoRoyalWorkshopSlotPlan>? workshopPlans,
  }) {
    final nextLegacyCount =
        unlockedWorkshopCount ?? legacyUnlockedWorkshopCount;
    final nextUnlockedIndices =
        unlockedWorkshopIndices ??
        (unlockedWorkshopCount == null
            ? this.unlockedWorkshopIndices
            : const <int>{});
    return BdoRoyalWorkshopAreaPlan(
      unlockedWorkshopCount: nextLegacyCount,
      unlockedWorkshopIndices: nextUnlockedIndices,
      activeWorkshopIndex: activeWorkshopIndex ?? this.activeWorkshopIndex,
      workerName: clearWorkerName ? '' : workerName ?? this.workerName,
      isRunning: isRunning ?? this.isRunning,
      workshopPlans: workshopPlans ?? this.workshopPlans,
    );
  }

  BdoRoyalWorkshopAreaPlan withWorkshopUnlocked(
    int workshopIndex, {
    required bool unlocked,
  }) {
    if (workshopIndex <= 0) return this;
    final next = <int>{...unlockedIndices, 0};
    if (unlocked) {
      next.add(workshopIndex);
    } else {
      next.remove(workshopIndex);
    }
    final nextActive = next.contains(activeWorkshopIndex)
        ? activeWorkshopIndex
        : 0;
    return copyWith(
      unlockedWorkshopIndices: Set<int>.unmodifiable(next),
      activeWorkshopIndex: nextActive,
      isRunning: false,
    );
  }

  BdoRoyalWorkshopAreaPlan normalizedFor(int maximumWorkshops) {
    final maximum = maximumWorkshops < 1 ? 1 : maximumWorkshops;
    final nextUnlocked = <int>{
      0,
      ...unlockedIndices.where((index) => index > 0 && index < maximum),
    };
    final nextActive = nextUnlocked.contains(activeWorkshopIndex)
        ? activeWorkshopIndex
        : 0;
    return BdoRoyalWorkshopAreaPlan(
      unlockedWorkshopCount: nextUnlocked.length,
      unlockedWorkshopIndices: Set<int>.unmodifiable(nextUnlocked),
      activeWorkshopIndex: nextActive,
      workerName: effectiveWorkerName,
      isRunning: effectiveIsRunning && planFor(nextActive).hasRecordedGood,
      workshopPlans: Map<int, BdoRoyalWorkshopSlotPlan>.unmodifiable(
        <int, BdoRoyalWorkshopSlotPlan>{
          for (final entry in workshopPlans.entries)
            if (entry.key >= 0 && entry.key < maximum)
              entry.key: entry.value.copyWith(
                clearWorkerName: true,
                isRunning: false,
              ),
        },
      ),
    );
  }

  BdoRoyalWorkshopAreaPlan withWorkshopPlan(
    int workshopIndex,
    BdoRoyalWorkshopSlotPlan plan,
  ) {
    return copyWith(
      workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
        ...workshopPlans,
        workshopIndex: plan,
      },
    );
  }

  BdoRoyalWorkshopAreaPlan withAreaRuntime({
    String? workerName,
    bool clearWorkerName = false,
    bool? isRunning,
  }) {
    final normalizedPlans = <int, BdoRoyalWorkshopSlotPlan>{
      for (final entry in workshopPlans.entries)
        entry.key: entry.value.copyWith(
          clearWorkerName: true,
          isRunning: false,
        ),
    };
    return copyWith(
      workerName: workerName,
      clearWorkerName: clearWorkerName,
      isRunning: isRunning,
      workshopPlans: normalizedPlans,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'unlockedWorkshopCount': unlockedWorkshopCount,
    'unlockedWorkshopIndices': unlockedIndices.toList()..sort(),
    'activeWorkshopIndex': normalizedActiveWorkshopIndex,
    if (effectiveWorkerName.isNotEmpty) 'workerName': effectiveWorkerName,
    if (effectiveIsRunning) 'isRunning': true,
    if (workshopPlans.isNotEmpty)
      'workshopPlans': <String, Object?>{
        for (final index in workshopPlans.keys.toList()..sort())
          '$index': workshopPlans[index]!
              .copyWith(clearWorkerName: true, isRunning: false)
              .toJson(),
      },
  };

  factory BdoRoyalWorkshopAreaPlan.fromJson(Object? json) {
    if (json is! Map) return const BdoRoyalWorkshopAreaPlan();
    final unlocked = _positiveInt(json['unlockedWorkshopCount']) ?? 1;
    final rawUnlockedIndices = json['unlockedWorkshopIndices'];
    final unlockedIndices = <int>{};
    if (rawUnlockedIndices is List) {
      for (final value in rawUnlockedIndices) {
        final index = _nonNegativeInt(value);
        if (index != null) unlockedIndices.add(index);
      }
    }
    final rawActiveIndex = _nonNegativeInt(json['activeWorkshopIndex']) ?? 0;
    final rawPlans = json['workshopPlans'];
    final plans = <int, BdoRoyalWorkshopSlotPlan>{};
    if (rawPlans is Map) {
      for (final entry in rawPlans.entries) {
        final index = _nonNegativeInt(entry.key);
        if (index != null) {
          plans[index] = BdoRoyalWorkshopSlotPlan.fromJson(entry.value);
        }
      }
    }

    // Schema 7 stored a single area's task directly on the area plan. Move it
    // into slot 0 so existing users keep every recorded value.
    if (plans.isEmpty &&
        (json.containsKey('selectedGoodId') ||
            json.containsKey('taskHours') ||
            json.containsKey('netSilverPerCycle') ||
            json['isRunning'] == true)) {
      plans[rawActiveIndex] = BdoRoyalWorkshopSlotPlan(
        selectedGoodId: _positiveInt(json['selectedGoodId']),
        taskHours: _positiveDouble(json['taskHours']),
        repeatCount: _positiveInt(json['repeatCount']) ?? 1,
        netSilverPerCycle: _nonNegativeDouble(json['netSilverPerCycle']),
      );
    }

    var activeIndex = rawActiveIndex;
    final hasAreaRuntime =
        json.containsKey('workerName') || json.containsKey('isRunning');
    if (!hasAreaRuntime) {
      final legacyRunning =
          plans.entries
              .where(
                (entry) =>
                    entry.key >= 0 &&
                    entry.key < unlocked &&
                    entry.value.isRunning,
              )
              .toList(growable: false)
            ..sort((left, right) => left.key.compareTo(right.key));
      if (legacyRunning.isNotEmpty) {
        activeIndex = legacyRunning.first.key;
      }
    }
    final activeLegacy = plans[activeIndex];
    var migratedWorkerName = '${json['workerName'] ?? ''}'.trim();
    if (migratedWorkerName.isEmpty) {
      migratedWorkerName = activeLegacy?.workerName.trim() ?? '';
    }
    if (migratedWorkerName.isEmpty) {
      for (final entry in plans.entries) {
        final candidate = entry.value.workerName.trim();
        if (candidate.isNotEmpty) {
          migratedWorkerName = candidate;
          break;
        }
      }
    }
    final migratedRunning = hasAreaRuntime
        ? json['isRunning'] == true
        : activeLegacy?.isRunning == true;
    final normalizedPlans = <int, BdoRoyalWorkshopSlotPlan>{
      for (final entry in plans.entries)
        entry.key: entry.value.copyWith(
          clearWorkerName: true,
          isRunning: false,
        ),
    };

    return BdoRoyalWorkshopAreaPlan(
      unlockedWorkshopCount: unlocked,
      unlockedWorkshopIndices: Set<int>.unmodifiable(unlockedIndices),
      activeWorkshopIndex: activeIndex,
      workerName: migratedWorkerName,
      isRunning: migratedRunning,
      workshopPlans: Map<int, BdoRoyalWorkshopSlotPlan>.unmodifiable(
        normalizedPlans,
      ),
    );
  }

  bool sameValuesAs(BdoRoyalWorkshopAreaPlan other) {
    if (!_sameIntSet(unlockedIndices, other.unlockedIndices) ||
        normalizedActiveWorkshopIndex != other.normalizedActiveWorkshopIndex ||
        effectiveWorkerName != other.effectiveWorkerName ||
        effectiveIsRunning != other.effectiveIsRunning ||
        workshopPlans.length != other.workshopPlans.length) {
      return false;
    }
    for (final entry in workshopPlans.entries) {
      final otherPlan = other.workshopPlans[entry.key];
      if (otherPlan == null || !entry.value.sameTaskValuesAs(otherPlan)) {
        return false;
      }
    }
    return true;
  }
}

class BdoRoyalWorkshopPlan {
  BdoRoyalWorkshopPlan({
    this.accessInvested = false,
    this.freeRefreshAvailable = true,
    Map<String, BdoRoyalWorkshopAreaPlan> areaPlans =
        const <String, BdoRoyalWorkshopAreaPlan>{},
  }) : areaPlans = Map<String, BdoRoyalWorkshopAreaPlan>.unmodifiable(
         <String, BdoRoyalWorkshopAreaPlan>{
           for (final entry in areaPlans.entries)
             if (bdoRoyalWorkshopAreasById[entry.key] case final area?)
               entry.key: entry.value.normalizedFor(area.maximumWorkshops),
         },
       );

  final bool accessInvested;
  final bool freeRefreshAvailable;
  final Map<String, BdoRoyalWorkshopAreaPlan> areaPlans;

  int get reservedContributionPoints =>
      accessInvested ? bdoRoyalWorkshopAccessContributionPoints : 0;

  int get assignedWorkerCount => areaPlans.values
      .where((areaPlan) => areaPlan.effectiveWorkerName.isNotEmpty)
      .length;
  int get runningTaskCount =>
      areaPlans.values.where((areaPlan) => areaPlan.effectiveIsRunning).length;

  Set<String> get duplicateWorkerNames {
    final counts = <String, int>{};
    final originalNames = <String, String>{};
    for (final areaPlan in areaPlans.values) {
      final worker = areaPlan.effectiveWorkerName.trim();
      if (worker.isEmpty) continue;
      final normalized = worker.toLowerCase();
      counts.update(normalized, (value) => value + 1, ifAbsent: () => 1);
      originalNames.putIfAbsent(normalized, () => worker);
    }
    return <String>{
      for (final entry in counts.entries)
        if (entry.value > 1) originalNames[entry.key]!,
    };
  }

  bool hasDuplicateWorkerName(String workerName) {
    final normalized = workerName.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return duplicateWorkerNames.any(
      (duplicate) => duplicate.trim().toLowerCase() == normalized,
    );
  }

  BdoRoyalWorkshopAreaPlan planFor(String areaId) =>
      areaPlans[areaId] ?? const BdoRoyalWorkshopAreaPlan();

  BdoRoyalWorkshopPlan copyWith({
    bool? accessInvested,
    bool? freeRefreshAvailable,
    Map<String, BdoRoyalWorkshopAreaPlan>? areaPlans,
  }) {
    return BdoRoyalWorkshopPlan(
      accessInvested: accessInvested ?? this.accessInvested,
      freeRefreshAvailable: freeRefreshAvailable ?? this.freeRefreshAvailable,
      areaPlans: areaPlans ?? this.areaPlans,
    );
  }

  BdoRoyalWorkshopPlan withAreaPlan(
    String areaId,
    BdoRoyalWorkshopAreaPlan plan,
  ) {
    return copyWith(
      areaPlans: <String, BdoRoyalWorkshopAreaPlan>{...areaPlans, areaId: plan},
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'accessInvested': accessInvested,
    'freeRefreshAvailable': freeRefreshAvailable,
    if (areaPlans.isNotEmpty)
      'areaPlans': <String, Object?>{
        for (final id in areaPlans.keys.toList()..sort())
          id: areaPlans[id]!.toJson(),
      },
  };

  factory BdoRoyalWorkshopPlan.fromJson(Object? json) {
    if (json is! Map) return BdoRoyalWorkshopPlan();
    final rawPlans = json['areaPlans'];
    final plans = <String, BdoRoyalWorkshopAreaPlan>{};
    if (rawPlans is Map) {
      for (final entry in rawPlans.entries) {
        final id = '${entry.key}'.trim();
        if (bdoRoyalWorkshopAreasById.containsKey(id)) {
          plans[id] = BdoRoyalWorkshopAreaPlan.fromJson(entry.value);
        }
      }
    }
    return BdoRoyalWorkshopPlan(
      accessInvested: json['accessInvested'] == true,
      freeRefreshAvailable: json['freeRefreshAvailable'] != false,
      areaPlans: plans,
    );
  }

  bool sameValuesAs(BdoRoyalWorkshopPlan other) {
    if (accessInvested != other.accessInvested ||
        freeRefreshAvailable != other.freeRefreshAvailable ||
        areaPlans.length != other.areaPlans.length) {
      return false;
    }
    for (final entry in areaPlans.entries) {
      final otherPlan = other.areaPlans[entry.key];
      if (otherPlan == null || !entry.value.sameValuesAs(otherPlan)) {
        return false;
      }
    }
    return true;
  }
}

class BdoRoyalWorkshopIncomeEstimate {
  const BdoRoyalWorkshopIncomeEstimate({
    required this.netSilverPerOnlineHour,
    required this.includedAreaCount,
    required this.excludedRareAreaCount,
    required this.incompleteAreaCount,
  });

  final double netSilverPerOnlineHour;
  final int includedAreaCount;
  final int excludedRareAreaCount;
  final int incompleteAreaCount;
}

BdoRoyalWorkshopIncomeEstimate estimateRoyalWorkshopIncome({
  required BdoRoyalWorkshopPlan plan,
  required Map<int, BdoRoyalWorkshopGood> goodsById,
}) {
  var hourly = 0.0;
  var included = 0;
  var excludedRare = 0;
  var incomplete = 0;
  if (!plan.accessInvested) {
    return const BdoRoyalWorkshopIncomeEstimate(
      netSilverPerOnlineHour: 0,
      includedAreaCount: 0,
      excludedRareAreaCount: 0,
      incompleteAreaCount: 0,
    );
  }
  for (final areaPlan in plan.areaPlans.values) {
    if (!areaPlan.effectiveIsRunning) continue;
    final slotPlan = areaPlan.activePlan;
    final good = goodsById[slotPlan.selectedGoodId];
    if (slotPlan.isRareOrSpecial || good?.rareRoll == true) {
      excludedRare += 1;
      continue;
    }
    final hours = slotPlan.taskHours;
    final net = slotPlan.netSilverPerCycle;
    if (!slotPlan.hasRecordedGood ||
        areaPlan.effectiveWorkerName.isEmpty ||
        plan.hasDuplicateWorkerName(areaPlan.effectiveWorkerName) ||
        hours == null ||
        hours <= 0 ||
        net == null) {
      incomplete += 1;
      continue;
    }
    hourly += (net * slotPlan.repeatCount) / hours;
    included += 1;
  }
  return BdoRoyalWorkshopIncomeEstimate(
    netSilverPerOnlineHour: hourly,
    includedAreaCount: included,
    excludedRareAreaCount: excludedRare,
    incompleteAreaCount: incomplete,
  );
}

int? _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}

double? _positiveDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
}

double? _nonNegativeDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
}

bool _sameIntSet(Set<int> left, Set<int> right) =>
    left.length == right.length && left.containsAll(right);
