enum BairogBenchmarkGoal { sharp, dust, caphras, sourceValue }

class BairogNostosMaterial {
  const BairogNostosMaterial({
    required this.itemId,
    required this.name,
    required this.gatheringActivity,
    required this.methodId,
    required this.iconAssetPath,
    required this.nativeIconPath,
  });

  final int itemId;
  final String name;
  final String gatheringActivity;
  final String methodId;
  final String iconAssetPath;
  final String nativeIconPath;
}

const bairogNostosMaterials = <BairogNostosMaterial>[
  BairogNostosMaterial(
    itemId: 821350,
    name: 'Cracked Terrashard',
    gatheringActivity: 'Hoe Gathering',
    methodId: 'hoe',
    iconAssetPath: 'assets/icons/items/821350.webp',
    nativeIconPath: 'icons/new_icon/03_etc/07_productmaterial/00821350.webp',
  ),
  BairogNostosMaterial(
    itemId: 821348,
    name: 'Withered Wood Chip',
    gatheringActivity: 'Lumbering',
    methodId: 'lumbering',
    iconAssetPath: 'assets/icons/items/821348.webp',
    nativeIconPath: 'icons/new_icon/03_etc/07_productmaterial/00821348.webp',
  ),
  BairogNostosMaterial(
    itemId: 821349,
    name: 'Thin Essence of Life',
    gatheringActivity: 'Fluid Collecting',
    methodId: 'fluid',
    iconAssetPath: 'assets/icons/items/821349.webp',
    nativeIconPath: 'icons/new_icon/03_etc/07_productmaterial/00821349.webp',
  ),
  BairogNostosMaterial(
    itemId: 821353,
    name: 'Dim Heartvein Shard',
    gatheringActivity: 'Mining',
    methodId: 'mining',
    iconAssetPath: 'assets/icons/items/821353.webp',
    nativeIconPath: 'icons/new_icon/03_etc/07_productmaterial/00821353.webp',
  ),
  BairogNostosMaterial(
    itemId: 821351,
    name: 'Faint Wildsoul',
    gatheringActivity: 'Butchering',
    methodId: 'butcher',
    iconAssetPath: 'assets/icons/items/821351.webp',
    nativeIconPath: 'icons/new_icon/03_etc/07_productmaterial/00821351.webp',
  ),
  BairogNostosMaterial(
    itemId: 821352,
    name: 'Faded Naturewoven Hide',
    gatheringActivity: 'Tanning',
    methodId: 'tanning',
    iconAssetPath: 'assets/icons/items/821352.webp',
    nativeIconPath: 'icons/new_icon/03_etc/07_productmaterial/00821352.webp',
  ),
];

BairogNostosMaterial? bairogNostosMaterialFor(int itemId) {
  for (final material in bairogNostosMaterials) {
    if (material.itemId == itemId) return material;
  }
  return null;
}

class BairogBenchmarkConditions {
  const BairogBenchmarkConditions({
    required this.region,
    required this.mastery,
    required this.gatheringDropRatePercent,
    required this.extraGatherPet,
    required this.minigame,
    required this.agris,
    required this.afuaru,
    required this.chestProcs,
    required this.chestProcsX10,
    required this.feverTime,
    required this.includeEvergreenShard,
    required this.afterTax,
    required this.marketNetRate,
    required this.energyPotionUnitsPerHour,
    required this.energyPotionCostPerHour,
  });

  final String region;
  final int mastery;
  final int gatheringDropRatePercent;
  final String extraGatherPet;
  final String minigame;
  final bool agris;
  final bool afuaru;
  final bool chestProcs;
  final bool chestProcsX10;
  final bool feverTime;
  final bool includeEvergreenShard;
  final bool afterTax;
  final double marketNetRate;
  final int energyPotionUnitsPerHour;
  final int energyPotionCostPerHour;

  String get compactLabel =>
      '$mastery mastery · $gatheringDropRatePercent% GDR · $region';
}

class BairogItemYield {
  const BairogItemYield({
    required this.itemId,
    required this.name,
    required this.perHour,
    this.vendorUnitPrice,
  });

  final int itemId;
  final String name;
  final double perHour;
  final int? vendorUnitPrice;
}

class BairogRouteYieldProfile {
  const BairogRouteYieldProfile({
    required this.primaryItemId,
    required this.primaryItemName,
    required this.primaryPerHour,
    required this.nostosItemId,
    required this.nostosItemName,
    required this.nostosPerHour,
    required this.blackGemFragmentPerHour,
    required this.sharpPerHour,
    required this.dustPerHour,
    required this.caphrasPerHour,
    required this.fairyPowderPerHour,
    required this.traceOfNaturePerHour,
    required this.lightstonePerHour,
    required this.deepBlueHoofRootPerHour,
    required this.evergreenShardPerHour,
    required this.fairysBreathPerHour,
    required this.massOfPureMagicPerHour,
    required this.lailasPetalPerHour,
    required this.gatheringExpArtifactPerHour,
    required this.gatheringMasteryArtifactPerHour,
    required this.gatheringDropRateArtifactPerHour,
    required this.lifeExpArtifactPerHour,
    required this.lifeMasteryArtifactPerHour,
  });

  final int primaryItemId;
  final String primaryItemName;
  final double primaryPerHour;
  final int nostosItemId;
  final String nostosItemName;
  final double nostosPerHour;
  final double blackGemFragmentPerHour;
  final double sharpPerHour;
  final double dustPerHour;
  final double caphrasPerHour;
  final double fairyPowderPerHour;
  final double traceOfNaturePerHour;
  final double lightstonePerHour;
  final double deepBlueHoofRootPerHour;
  final double evergreenShardPerHour;
  final double fairysBreathPerHour;
  final double massOfPureMagicPerHour;
  final double lailasPetalPerHour;
  final double gatheringExpArtifactPerHour;
  final double gatheringMasteryArtifactPerHour;
  final double gatheringDropRateArtifactPerHour;
  final double lifeExpArtifactPerHour;
  final double lifeMasteryArtifactPerHour;

  Iterable<BairogItemYield> get items sync* {
    yield BairogItemYield(
      itemId: primaryItemId,
      name: primaryItemName,
      perHour: primaryPerHour,
    );
    yield BairogItemYield(
      itemId: nostosItemId,
      name: nostosItemName,
      perHour: nostosPerHour,
    );
    yield BairogItemYield(
      itemId: 4999,
      name: 'Black Gem Fragment',
      perHour: blackGemFragmentPerHour,
    );
    yield BairogItemYield(
      itemId: 4998,
      name: 'Sharp Black Crystal Shard',
      perHour: sharpPerHour,
    );
    yield BairogItemYield(
      itemId: 721002,
      name: 'Ancient Spirit Dust',
      perHour: dustPerHour,
    );
    yield BairogItemYield(
      itemId: 721003,
      name: 'Caphras Stone',
      perHour: caphrasPerHour,
    );
    yield BairogItemYield(
      itemId: 5651,
      name: 'Fairy Powder',
      perHour: fairyPowderPerHour,
      vendorUnitPrice: 10000,
    );
    yield BairogItemYield(
      itemId: 5960,
      name: 'Trace of Nature',
      perHour: traceOfNaturePerHour,
    );
    yield BairogItemYield(
      itemId: 766107,
      name: 'Imperfect Lightstone of Flora',
      perHour: lightstonePerHour,
    );
    yield BairogItemYield(
      itemId: 50810,
      name: 'Deep Blue Hoof Root',
      perHour: deepBlueHoofRootPerHour,
    );
    yield BairogItemYield(
      itemId: 821469,
      name: 'Evergreen Shard',
      perHour: evergreenShardPerHour,
    );
    yield BairogItemYield(
      itemId: 821371,
      name: "Fairy's Breath",
      perHour: fairysBreathPerHour,
    );
    yield BairogItemYield(
      itemId: 752023,
      name: 'Mass of Pure Magic',
      perHour: massOfPureMagicPerHour,
    );
    yield BairogItemYield(
      itemId: 54031,
      name: "Laila's Petal",
      perHour: lailasPetalPerHour,
    );
    yield BairogItemYield(
      itemId: 735356,
      name: "Sethra's Artifact - Gathering EXP",
      perHour: gatheringExpArtifactPerHour,
    );
    yield BairogItemYield(
      itemId: 735367,
      name: "Sethra's Artifact - Gathering Mastery",
      perHour: gatheringMasteryArtifactPerHour,
    );
    yield BairogItemYield(
      itemId: 735353,
      name: "Sethra's Artifact - Gathering Item Drop Rate",
      perHour: gatheringDropRateArtifactPerHour,
    );
    yield BairogItemYield(
      itemId: 735351,
      name: "Sethra's Artifact - Life EXP",
      perHour: lifeExpArtifactPerHour,
    );
    yield BairogItemYield(
      itemId: 735352,
      name: "Sethra's Artifact - Life Skill Mastery",
      perHour: lifeMasteryArtifactPerHour,
    );
  }

  BairogItemYield? item(int itemId) {
    for (final item in items) {
      if (item.itemId == itemId) return item;
    }
    return null;
  }
}

class BairogRouteBenchmark {
  const BairogRouteBenchmark({
    required this.sourceRouteId,
    required this.sourceRouteName,
    required this.spotId,
    required this.methodId,
    required this.videoUrl,
    required this.gathersPerHour,
    required this.sourceSessionCount,
    required this.sourceHours,
    required this.sourceUpdatedOn,
    required this.sharpPerHour,
    required this.dustPerHour,
    required this.caphrasPerHour,
    required this.sourceSilverAfterTaxPerHour,
    required this.yieldProfile,
  });

  final int sourceRouteId;
  final String sourceRouteName;
  final String? spotId;
  final String methodId;
  final String videoUrl;
  final int gathersPerHour;
  final int sourceSessionCount;
  final double sourceHours;
  final String sourceUpdatedOn;
  final double sharpPerHour;
  final double dustPerHour;
  final double caphrasPerHour;
  final int sourceSilverAfterTaxPerHour;
  final BairogRouteYieldProfile yieldProfile;

  bool get isMapped => spotId != null;

  Iterable<BairogItemYield> get itemYields => yieldProfile.items;

  BairogItemYield get nostosYield => itemYield(yieldProfile.nostosItemId)!;

  BairogItemYield? itemYield(int itemId) => yieldProfile.item(itemId);

  double score(BairogBenchmarkGoal goal) => switch (goal) {
    BairogBenchmarkGoal.sharp => sharpPerHour,
    BairogBenchmarkGoal.dust => dustPerHour,
    BairogBenchmarkGoal.caphras => caphrasPerHour,
    BairogBenchmarkGoal.sourceValue => sourceSilverAfterTaxPerHour.toDouble(),
  };
}

class BairogBenchmarkSet {
  const BairogBenchmarkSet({
    required this.id,
    required this.creator,
    required this.publisher,
    required this.calculatorUrl,
    required this.capturedOn,
    required this.conditions,
    required this.routes,
  });

  final String id;
  final String creator;
  final String publisher;
  final String calculatorUrl;
  final String capturedOn;
  final BairogBenchmarkConditions conditions;
  final List<BairogRouteBenchmark> routes;

  String get visibleCredit => '$creator · $publisher';

  Iterable<BairogRouteBenchmark> get mappedRoutes =>
      routes.where((route) => route.isMapped);

  Iterable<BairogRouteBenchmark> get unmappedRoutes =>
      routes.where((route) => !route.isMapped);

  BairogRouteBenchmark? bestForSpot(
    String spotId,
    BairogBenchmarkGoal goal, {
    String? methodId,
  }) {
    BairogRouteBenchmark? best;
    for (final route in mappedRoutes) {
      if (route.spotId != spotId ||
          (methodId != null && route.methodId != methodId)) {
        continue;
      }
      if (best == null || route.score(goal) > best.score(goal)) best = route;
    }
    return best;
  }
}

const bairogBenchmarkSet = BairogBenchmarkSet(
  id: 'bdoworkshop-gathering-eu-2026-09-02',
  creator: 'Bairog Haan',
  publisher: 'BDO Workshop',
  calculatorUrl: 'https://bdoworkshop.com/gathering-calculator',
  capturedOn: '2026-09-02',
  conditions: BairogBenchmarkConditions(
    region: 'EU',
    mastery: 2000,
    gatheringDropRatePercent: 60,
    extraGatherPet: 'None',
    minigame: 'Normal (5%)',
    agris: false,
    afuaru: true,
    chestProcs: true,
    chestProcsX10: false,
    feverTime: true,
    includeEvergreenShard: true,
    afterTax: true,
    marketNetRate: 0.845,
    energyPotionUnitsPerHour: 6,
    energyPotionCostPerHour: 18800000,
  ),
  routes: <BairogRouteBenchmark>[
    BairogRouteBenchmark(
      sourceRouteId: 36,
      sourceRouteName: 'Northwestern Gateway Lizard',
      spotId: 'northwestern-lizards',
      methodId: 'tanning',
      videoUrl: 'https://youtu.be/4OdS5-yOsiQ',
      gathersPerHour: 878,
      sourceSessionCount: 4,
      sourceHours: 4.7,
      sourceUpdatedOn: '2026-06-19',
      sharpPerHour: 381,
      dustPerHour: 98,
      caphrasPerHour: 9,
      sourceSilverAfterTaxPerHour: 2150000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 6008,
        primaryItemName: 'Lizard Hide',
        primaryPerHour: 22279,
        nostosItemId: 821352,
        nostosItemName: 'Faded Naturewoven Hide',
        nostosPerHour: 80,
        blackGemFragmentPerHour: 573,
        sharpPerHour: 381,
        dustPerHour: 98,
        caphrasPerHour: 9,
        fairyPowderPerHour: 927,
        traceOfNaturePerHour: 115,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 6,
        evergreenShardPerHour: 0.30,
        fairysBreathPerHour: 1073,
        massOfPureMagicPerHour: 0.20,
        lailasPetalPerHour: 7,
        gatheringExpArtifactPerHour: 0.16,
        gatheringMasteryArtifactPerHour: 0.19,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.20,
        lifeMasteryArtifactPerHour: 0.23,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 38,
      sourceRouteName: 'Imp Cave Wolves',
      spotId: 'imp-cave-wolves',
      methodId: 'tanning',
      videoUrl: 'https://youtu.be/M8HdXKjzERs?si=VV1XFrTaxub3ciq7',
      gathersPerHour: 856,
      sourceSessionCount: 1,
      sourceHours: 1,
      sourceUpdatedOn: '2026-06-16',
      sharpPerHour: 371,
      dustPerHour: 96,
      caphrasPerHour: 9,
      sourceSilverAfterTaxPerHour: 2060000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 6014,
        primaryItemName: 'Wolf Hide',
        primaryPerHour: 21721,
        nostosItemId: 821352,
        nostosItemName: 'Faded Naturewoven Hide',
        nostosPerHour: 78,
        blackGemFragmentPerHour: 558,
        sharpPerHour: 371,
        dustPerHour: 96,
        caphrasPerHour: 9,
        fairyPowderPerHour: 904,
        traceOfNaturePerHour: 112,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 6,
        evergreenShardPerHour: 0.29,
        fairysBreathPerHour: 1046,
        massOfPureMagicPerHour: 0.20,
        lailasPetalPerHour: 7,
        gatheringExpArtifactPerHour: 0.16,
        gatheringMasteryArtifactPerHour: 0.19,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.20,
        lifeMasteryArtifactPerHour: 0.22,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 37,
      sourceRouteName: 'Bher Elk',
      spotId: 'behr-deer',
      methodId: 'tanning',
      videoUrl: 'https://youtu.be/HOxEDCiDgsI?si=c8jDijojDoVpNHYV',
      gathersPerHour: 850,
      sourceSessionCount: 7,
      sourceHours: 6.5,
      sourceUpdatedOn: '2026-06-16',
      sharpPerHour: 368,
      dustPerHour: 95,
      caphrasPerHour: 9,
      sourceSilverAfterTaxPerHour: 2050000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 6001,
        primaryItemName: 'Deer Hide',
        primaryPerHour: 21569,
        nostosItemId: 821352,
        nostosItemName: 'Faded Naturewoven Hide',
        nostosPerHour: 78,
        blackGemFragmentPerHour: 554,
        sharpPerHour: 368,
        dustPerHour: 95,
        caphrasPerHour: 9,
        fairyPowderPerHour: 898,
        traceOfNaturePerHour: 112,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 6,
        evergreenShardPerHour: 0.29,
        fairysBreathPerHour: 1039,
        massOfPureMagicPerHour: 0.20,
        lailasPetalPerHour: 7,
        gatheringExpArtifactPerHour: 0.16,
        gatheringMasteryArtifactPerHour: 0.18,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.19,
        lifeMasteryArtifactPerHour: 0.22,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 47,
      sourceRouteName: 'Serendia sheep mountain',
      spotId: 'sheep-mountain',
      methodId: 'tanning',
      videoUrl: 'https://www.youtube.com/watch?v=lySkpq5wYfs',
      gathersPerHour: 1039,
      sourceSessionCount: 13,
      sourceHours: 15.6,
      sourceUpdatedOn: '2026-06-29',
      sharpPerHour: 368,
      dustPerHour: 102,
      caphrasPerHour: 10,
      sourceSilverAfterTaxPerHour: 2130000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 6002,
        primaryItemName: 'Sheep Hide',
        primaryPerHour: 22598,
        nostosItemId: 821352,
        nostosItemName: 'Faded Naturewoven Hide',
        nostosPerHour: 100,
        blackGemFragmentPerHour: 538,
        sharpPerHour: 368,
        dustPerHour: 102,
        caphrasPerHour: 10,
        fairyPowderPerHour: 1086,
        traceOfNaturePerHour: 131,
        lightstonePerHour: 7,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.36,
        fairysBreathPerHour: 1019,
        massOfPureMagicPerHour: 0.24,
        lailasPetalPerHour: 9,
        gatheringExpArtifactPerHour: 0.19,
        gatheringMasteryArtifactPerHour: 0.22,
        gatheringDropRateArtifactPerHour: 0.14,
        lifeExpArtifactPerHour: 0.24,
        lifeMasteryArtifactPerHour: 0.27,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 17,
      sourceRouteName: 'Wolves at Imp Cave',
      spotId: 'imp-cave-wolves',
      methodId: 'butcher',
      videoUrl: 'https://youtu.be/M8HdXKjzERs?si=VV1XFrTaxub3ciq7',
      gathersPerHour: 930,
      sourceSessionCount: 8,
      sourceHours: 10,
      sourceUpdatedOn: '2026-07-06',
      sharpPerHour: 284,
      dustPerHour: 102,
      caphrasPerHour: 10,
      sourceSilverAfterTaxPerHour: 2030000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 7901,
        primaryItemName: 'Wolf Meat',
        primaryPerHour: 20228,
        nostosItemId: 821351,
        nostosItemName: 'Faint Wildsoul',
        nostosPerHour: 116,
        blackGemFragmentPerHour: 589,
        sharpPerHour: 284,
        dustPerHour: 102,
        caphrasPerHour: 10,
        fairyPowderPerHour: 969,
        traceOfNaturePerHour: 117,
        lightstonePerHour: 7,
        deepBlueHoofRootPerHour: 6,
        evergreenShardPerHour: 0.32,
        fairysBreathPerHour: 1131,
        massOfPureMagicPerHour: 0.21,
        lailasPetalPerHour: 7,
        gatheringExpArtifactPerHour: 0.17,
        gatheringMasteryArtifactPerHour: 0.20,
        gatheringDropRateArtifactPerHour: 0.12,
        lifeExpArtifactPerHour: 0.21,
        lifeMasteryArtifactPerHour: 0.24,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 51,
      sourceRouteName: 'Lions at Ancado Coast',
      spotId: 'ancado-lions',
      methodId: 'butcher',
      videoUrl: 'https://youtu.be/vhFmboBdTQo',
      gathersPerHour: 837,
      sourceSessionCount: 2,
      sourceHours: 2,
      sourceUpdatedOn: '2026-08-03',
      sharpPerHour: 255,
      dustPerHour: 92,
      caphrasPerHour: 9,
      sourceSilverAfterTaxPerHour: 2290000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 7923,
        primaryItemName: 'Lion Meat',
        primaryPerHour: 18205,
        nostosItemId: 821351,
        nostosItemName: 'Faint Wildsoul',
        nostosPerHour: 104,
        blackGemFragmentPerHour: 530,
        sharpPerHour: 255,
        dustPerHour: 92,
        caphrasPerHour: 9,
        fairyPowderPerHour: 872,
        traceOfNaturePerHour: 105,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 6,
        evergreenShardPerHour: 0.29,
        fairysBreathPerHour: 1018,
        massOfPureMagicPerHour: 0.19,
        lailasPetalPerHour: 7,
        gatheringExpArtifactPerHour: 0.15,
        gatheringMasteryArtifactPerHour: 0.18,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.19,
        lifeMasteryArtifactPerHour: 0.22,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 41,
      sourceRouteName: "Pilgrim's Heaven",
      spotId: 'pilgrims-haven-stone',
      methodId: 'mining',
      videoUrl: 'https://youtu.be/TI6fmKCP5Og?si=ragL7D1uVfdWEv5c',
      gathersPerHour: 1036,
      sourceSessionCount: 10,
      sourceHours: 10,
      sourceUpdatedOn: '2026-06-16',
      sharpPerHour: 243,
      dustPerHour: 243,
      caphrasPerHour: 21,
      sourceSilverAfterTaxPerHour: 1710000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 4006,
        primaryItemName: 'Rough Stone',
        primaryPerHour: 22533,
        nostosItemId: 821353,
        nostosItemName: 'Dim Heartvein Shard',
        nostosPerHour: 115,
        blackGemFragmentPerHour: 94,
        sharpPerHour: 243,
        dustPerHour: 243,
        caphrasPerHour: 21,
        fairyPowderPerHour: 1053,
        traceOfNaturePerHour: 128,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 7,
        evergreenShardPerHour: 0.35,
        fairysBreathPerHour: 1002,
        massOfPureMagicPerHour: 0.24,
        lailasPetalPerHour: 7,
        gatheringExpArtifactPerHour: 0.19,
        gatheringMasteryArtifactPerHour: 0.22,
        gatheringDropRateArtifactPerHour: 0.14,
        lifeExpArtifactPerHour: 0.24,
        lifeMasteryArtifactPerHour: 0.27,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 39,
      sourceRouteName: 'Behr Wild herbs',
      spotId: 'behr-herbs',
      methodId: 'hoe',
      videoUrl: 'https://youtu.be/2IiTI4WtE08?si=mG6TDeNa2kM9Lje5',
      gathersPerHour: 1042,
      sourceSessionCount: 11,
      sourceHours: 10.2,
      sourceUpdatedOn: '2026-06-16',
      sharpPerHour: 232,
      dustPerHour: 186,
      caphrasPerHour: 17,
      sourceSilverAfterTaxPerHour: 1970000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 5439,
        primaryItemName: 'Wild Grass',
        primaryPerHour: 22664,
        nostosItemId: 821350,
        nostosItemName: 'Cracked Terrashard',
        nostosPerHour: 109,
        blackGemFragmentPerHour: 211,
        sharpPerHour: 232,
        dustPerHour: 186,
        caphrasPerHour: 17,
        fairyPowderPerHour: 1463,
        traceOfNaturePerHour: 144,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 3,
        evergreenShardPerHour: 0.36,
        fairysBreathPerHour: 1075,
        massOfPureMagicPerHour: 0.24,
        lailasPetalPerHour: 8,
        gatheringExpArtifactPerHour: 0.19,
        gatheringMasteryArtifactPerHour: 0.23,
        gatheringDropRateArtifactPerHour: 0.14,
        lifeExpArtifactPerHour: 0.24,
        lifeMasteryArtifactPerHour: 0.27,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 35,
      sourceRouteName: 'North Kaia Mountaintop',
      spotId: 'north-kaia-trees',
      methodId: 'lumbering',
      videoUrl: 'https://youtu.be/sAsZ5_onf0s?si=kTpKVpmG2nfeBjPl',
      gathersPerHour: 853,
      sourceSessionCount: 10,
      sourceHours: 10.7,
      sourceUpdatedOn: '2026-06-16',
      sharpPerHour: 232,
      dustPerHour: 1353,
      caphrasPerHour: 130,
      sourceSilverAfterTaxPerHour: 1890000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 4607,
        primaryItemName: 'Cedar Timber',
        primaryPerHour: 18553,
        nostosItemId: 821348,
        nostosItemName: 'Withered Wood Chip',
        nostosPerHour: 105,
        blackGemFragmentPerHour: 6,
        sharpPerHour: 232,
        dustPerHour: 1353,
        caphrasPerHour: 130,
        fairyPowderPerHour: 835,
        traceOfNaturePerHour: 124,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 7,
        evergreenShardPerHour: 0.29,
        fairysBreathPerHour: 1221,
        massOfPureMagicPerHour: 0.20,
        lailasPetalPerHour: 9,
        gatheringExpArtifactPerHour: 0.16,
        gatheringMasteryArtifactPerHour: 0.18,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.19,
        lifeMasteryArtifactPerHour: 0.22,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 48,
      sourceRouteName: 'Snake and Scorpions at Tshira Ruins',
      spotId: 'tshira-snake-scorpion',
      methodId: 'butcher',
      videoUrl: 'https://www.youtube.com/watch?v=eFHD9QK_HIo',
      gathersPerHour: 749,
      sourceSessionCount: 4,
      sourceHours: 3.4,
      sourceUpdatedOn: '2026-07-04',
      sharpPerHour: 228,
      dustPerHour: 82,
      caphrasPerHour: 8,
      sourceSilverAfterTaxPerHour: 2100000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 7922,
        primaryItemName: 'Snake Meat',
        primaryPerHour: 16291,
        nostosItemId: 821351,
        nostosItemName: 'Faint Wildsoul',
        nostosPerHour: 93,
        blackGemFragmentPerHour: 474,
        sharpPerHour: 228,
        dustPerHour: 82,
        caphrasPerHour: 8,
        fairyPowderPerHour: 780,
        traceOfNaturePerHour: 94,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.26,
        fairysBreathPerHour: 911,
        massOfPureMagicPerHour: 0.17,
        lailasPetalPerHour: 6,
        gatheringExpArtifactPerHour: 0.14,
        gatheringMasteryArtifactPerHour: 0.16,
        gatheringDropRateArtifactPerHour: 0.10,
        lifeExpArtifactPerHour: 0.17,
        lifeMasteryArtifactPerHour: 0.19,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 49,
      sourceRouteName: 'Snake at Gorgo Rock Belt',
      spotId: 'gorgo-cobras',
      methodId: 'butcher',
      videoUrl: 'https://youtu.be/htuq7Fg_6To',
      gathersPerHour: 739,
      sourceSessionCount: 4,
      sourceHours: 3.7,
      sourceUpdatedOn: '2026-08-03',
      sharpPerHour: 225,
      dustPerHour: 81,
      caphrasPerHour: 8,
      sourceSilverAfterTaxPerHour: 1960000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 7922,
        primaryItemName: 'Snake Meat',
        primaryPerHour: 16073,
        nostosItemId: 821351,
        nostosItemName: 'Faint Wildsoul',
        nostosPerHour: 92,
        blackGemFragmentPerHour: 468,
        sharpPerHour: 225,
        dustPerHour: 81,
        caphrasPerHour: 8,
        fairyPowderPerHour: 770,
        traceOfNaturePerHour: 93,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.25,
        fairysBreathPerHour: 899,
        massOfPureMagicPerHour: 0.17,
        lailasPetalPerHour: 6,
        gatheringExpArtifactPerHour: 0.14,
        gatheringMasteryArtifactPerHour: 0.16,
        gatheringDropRateArtifactPerHour: 0.10,
        lifeExpArtifactPerHour: 0.17,
        lifeMasteryArtifactPerHour: 0.19,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 42,
      sourceRouteName: 'Caphras Trees',
      spotId: 'edania-caphras-trees',
      methodId: 'lumbering',
      videoUrl: 'https://youtu.be/4NFkNLqwloY',
      gathersPerHour: 702,
      sourceSessionCount: 14,
      sourceHours: 13.4,
      sourceUpdatedOn: '2026-06-19',
      sharpPerHour: 221,
      dustPerHour: 1151,
      caphrasPerHour: 117,
      sourceSilverAfterTaxPerHour: 1850000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 821116,
        primaryItemName: 'Caphras Tree Timber',
        primaryPerHour: 15269,
        nostosItemId: 821348,
        nostosItemName: 'Withered Wood Chip',
        nostosPerHour: 92,
        blackGemFragmentPerHour: 5,
        sharpPerHour: 221,
        dustPerHour: 1151,
        caphrasPerHour: 117,
        fairyPowderPerHour: 727,
        traceOfNaturePerHour: 106,
        lightstonePerHour: 7,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.24,
        fairysBreathPerHour: 1072,
        massOfPureMagicPerHour: 0.16,
        lailasPetalPerHour: 8,
        gatheringExpArtifactPerHour: 0.13,
        gatheringMasteryArtifactPerHour: 0.15,
        gatheringDropRateArtifactPerHour: 0.09,
        lifeExpArtifactPerHour: 0.16,
        lifeMasteryArtifactPerHour: 0.18,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 50,
      sourceRouteName: 'Scorpions at Atumach',
      spotId: null,
      methodId: 'butcher',
      videoUrl: 'https://youtu.be/zzUCv7IvDZA',
      gathersPerHour: 617,
      sourceSessionCount: 1,
      sourceHours: 1,
      sourceUpdatedOn: '2026-08-03',
      sharpPerHour: 188,
      dustPerHour: 67,
      caphrasPerHour: 6,
      sourceSilverAfterTaxPerHour: 1910000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 7924,
        primaryItemName: 'Scorpion Meat',
        primaryPerHour: 13420,
        nostosItemId: 821351,
        nostosItemName: 'Faint Wildsoul',
        nostosPerHour: 77,
        blackGemFragmentPerHour: 391,
        sharpPerHour: 188,
        dustPerHour: 67,
        caphrasPerHour: 6,
        fairyPowderPerHour: 643,
        traceOfNaturePerHour: 77,
        lightstonePerHour: 5,
        deepBlueHoofRootPerHour: 4,
        evergreenShardPerHour: 0.21,
        fairysBreathPerHour: 750,
        massOfPureMagicPerHour: 0.14,
        lailasPetalPerHour: 5,
        gatheringExpArtifactPerHour: 0.11,
        gatheringMasteryArtifactPerHour: 0.13,
        gatheringDropRateArtifactPerHour: 0.08,
        lifeExpArtifactPerHour: 0.14,
        lifeMasteryArtifactPerHour: 0.16,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 43,
      sourceRouteName: 'Forest of Seclusion - fox',
      spotId: 'forest-seclusion-foxes',
      methodId: 'fluid',
      videoUrl: 'https://youtu.be/C4izfVS_SO4?si=8JAPvNkkikSSf2VC',
      gathersPerHour: 1035,
      sourceSessionCount: 10,
      sourceHours: 10,
      sourceUpdatedOn: '2026-06-16',
      sharpPerHour: 183,
      dustPerHour: 124,
      caphrasPerHour: 10,
      sourceSilverAfterTaxPerHour: 2090000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 6210,
        primaryItemName: 'Fox Blood',
        primaryPerHour: 22511,
        nostosItemId: 821349,
        nostosItemName: 'Thin Essence of Life',
        nostosPerHour: 99,
        blackGemFragmentPerHour: 498,
        sharpPerHour: 183,
        dustPerHour: 124,
        caphrasPerHour: 10,
        fairyPowderPerHour: 1094,
        traceOfNaturePerHour: 122,
        lightstonePerHour: 4,
        deepBlueHoofRootPerHour: 8,
        evergreenShardPerHour: 0.35,
        fairysBreathPerHour: 967,
        massOfPureMagicPerHour: 0.24,
        lailasPetalPerHour: 6,
        gatheringExpArtifactPerHour: 0.19,
        gatheringMasteryArtifactPerHour: 0.22,
        gatheringDropRateArtifactPerHour: 0.14,
        lifeExpArtifactPerHour: 0.24,
        lifeMasteryArtifactPerHour: 0.27,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 34,
      sourceRouteName: "Stillcoral Grove's Coral Crabs",
      spotId: 'stillcoral-rusalka-mining',
      methodId: 'mining',
      videoUrl: 'https://youtu.be/q8n_v9zdSfw',
      gathersPerHour: 742,
      sourceSessionCount: 10,
      sourceHours: 16,
      sourceUpdatedOn: '2026-06-19',
      sharpPerHour: 180,
      dustPerHour: 180,
      caphrasPerHour: 14,
      sourceSilverAfterTaxPerHour: 1780000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 4006,
        primaryItemName: 'Rough Stone',
        primaryPerHour: 8069,
        nostosItemId: 821353,
        nostosItemName: 'Dim Heartvein Shard',
        nostosPerHour: 74,
        blackGemFragmentPerHour: 69,
        sharpPerHour: 180,
        dustPerHour: 180,
        caphrasPerHour: 14,
        fairyPowderPerHour: 791,
        traceOfNaturePerHour: 81,
        lightstonePerHour: 4,
        deepBlueHoofRootPerHour: 4,
        evergreenShardPerHour: 0.25,
        fairysBreathPerHour: 734,
        massOfPureMagicPerHour: 0.17,
        lailasPetalPerHour: 6,
        gatheringExpArtifactPerHour: 0.14,
        gatheringMasteryArtifactPerHour: 0.16,
        gatheringDropRateArtifactPerHour: 0.10,
        lifeExpArtifactPerHour: 0.17,
        lifeMasteryArtifactPerHour: 0.19,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 40,
      sourceRouteName: "Biraghi's Den - Ash sap",
      spotId: null,
      methodId: 'fluid',
      videoUrl: 'https://youtu.be/qFICJfx824o',
      gathersPerHour: 872,
      sourceSessionCount: 10,
      sourceHours: 10,
      sourceUpdatedOn: '2026-06-19',
      sharpPerHour: 158,
      dustPerHour: 1016,
      caphrasPerHour: 104,
      sourceSilverAfterTaxPerHour: 2210000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 5001,
        primaryItemName: 'Ash Sap',
        primaryPerHour: 29863,
        nostosItemId: 821349,
        nostosItemName: 'Thin Essence of Life',
        nostosPerHour: 107,
        blackGemFragmentPerHour: 6,
        sharpPerHour: 158,
        dustPerHour: 1016,
        caphrasPerHour: 104,
        fairyPowderPerHour: 912,
        traceOfNaturePerHour: 137,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.30,
        fairysBreathPerHour: 1319,
        massOfPureMagicPerHour: 0.20,
        lailasPetalPerHour: 8,
        gatheringExpArtifactPerHour: 0.16,
        gatheringMasteryArtifactPerHour: 0.19,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.20,
        lifeMasteryArtifactPerHour: 0.23,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 44,
      sourceRouteName: 'Bloody Monastery Cedar sap',
      spotId: null,
      methodId: 'fluid',
      videoUrl: 'https://youtu.be/pRL3akht-8Q',
      gathersPerHour: 852,
      sourceSessionCount: 6,
      sourceHours: 5.7,
      sourceUpdatedOn: '2026-06-26',
      sharpPerHour: 155,
      dustPerHour: 992,
      caphrasPerHour: 101,
      sourceSilverAfterTaxPerHour: 1590000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 5010,
        primaryItemName: 'Cedar Sap',
        primaryPerHour: 29179,
        nostosItemId: 821349,
        nostosItemName: 'Thin Essence of Life',
        nostosPerHour: 104,
        blackGemFragmentPerHour: 6,
        sharpPerHour: 155,
        dustPerHour: 992,
        caphrasPerHour: 101,
        fairyPowderPerHour: 891,
        traceOfNaturePerHour: 133,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.29,
        fairysBreathPerHour: 1289,
        massOfPureMagicPerHour: 0.20,
        lailasPetalPerHour: 8,
        gatheringExpArtifactPerHour: 0.16,
        gatheringMasteryArtifactPerHour: 0.18,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.19,
        lifeMasteryArtifactPerHour: 0.22,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 45,
      sourceRouteName: "Eilton's snowfield cedar sap",
      spotId: 'snowfield-cedar',
      methodId: 'fluid',
      videoUrl: 'https://youtu.be/ILI51QJ9kIg',
      gathersPerHour: 827,
      sourceSessionCount: 5,
      sourceHours: 5,
      sourceUpdatedOn: '2026-06-26',
      sharpPerHour: 150,
      dustPerHour: 963,
      caphrasPerHour: 98,
      sourceSilverAfterTaxPerHour: 2330000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 5024,
        primaryItemName: 'Snowfield Cedar Sap',
        primaryPerHour: 28322,
        nostosItemId: 821349,
        nostosItemName: 'Thin Essence of Life',
        nostosPerHour: 101,
        blackGemFragmentPerHour: 6,
        sharpPerHour: 150,
        dustPerHour: 963,
        caphrasPerHour: 98,
        fairyPowderPerHour: 865,
        traceOfNaturePerHour: 129,
        lightstonePerHour: 6,
        deepBlueHoofRootPerHour: 5,
        evergreenShardPerHour: 0.28,
        fairysBreathPerHour: 1251,
        massOfPureMagicPerHour: 0.19,
        lailasPetalPerHour: 8,
        gatheringExpArtifactPerHour: 0.15,
        gatheringMasteryArtifactPerHour: 0.18,
        gatheringDropRateArtifactPerHour: 0.11,
        lifeExpArtifactPerHour: 0.19,
        lifeMasteryArtifactPerHour: 0.21,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 52,
      sourceRouteName: 'Caphras trees',
      spotId: 'edania-caphras-trees',
      methodId: 'fluid',
      videoUrl: 'https://youtu.be/4NFkNLqwloY',
      gathersPerHour: 770,
      sourceSessionCount: 11,
      sourceHours: 11,
      sourceUpdatedOn: '2026-07-10',
      sharpPerHour: 135,
      dustPerHour: 885,
      caphrasPerHour: 86,
      sourceSilverAfterTaxPerHour: 1620000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 5025,
        primaryItemName: 'Caphras Tree Sap',
        primaryPerHour: 25964,
        nostosItemId: 821349,
        nostosItemName: 'Thin Essence of Life',
        nostosPerHour: 95,
        blackGemFragmentPerHour: 5,
        sharpPerHour: 135,
        dustPerHour: 885,
        caphrasPerHour: 86,
        fairyPowderPerHour: 799,
        traceOfNaturePerHour: 119,
        lightstonePerHour: 7,
        deepBlueHoofRootPerHour: 6,
        evergreenShardPerHour: 0.26,
        fairysBreathPerHour: 1131,
        massOfPureMagicPerHour: 0.18,
        lailasPetalPerHour: 8,
        gatheringExpArtifactPerHour: 0.14,
        gatheringMasteryArtifactPerHour: 0.17,
        gatheringDropRateArtifactPerHour: 0.10,
        lifeExpArtifactPerHour: 0.18,
        lifeMasteryArtifactPerHour: 0.20,
      ),
    ),
    BairogRouteBenchmark(
      sourceRouteId: 46,
      sourceRouteName: 'Seoul Thuja sap',
      spotId: null,
      methodId: 'fluid',
      videoUrl: 'https://youtu.be/lD-8E-PnIyE',
      gathersPerHour: 693,
      sourceSessionCount: 4,
      sourceHours: 3.8,
      sourceUpdatedOn: '2026-07-31',
      sharpPerHour: 126,
      dustPerHour: 807,
      caphrasPerHour: 82,
      sourceSilverAfterTaxPerHour: 1940000000,
      yieldProfile: BairogRouteYieldProfile(
        primaryItemId: 5020,
        primaryItemName: 'Thuja Sap',
        primaryPerHour: 23733,
        nostosItemId: 821349,
        nostosItemName: 'Thin Essence of Life',
        nostosPerHour: 85,
        blackGemFragmentPerHour: 5,
        sharpPerHour: 126,
        dustPerHour: 807,
        caphrasPerHour: 82,
        fairyPowderPerHour: 725,
        traceOfNaturePerHour: 108,
        lightstonePerHour: 5,
        deepBlueHoofRootPerHour: 4,
        evergreenShardPerHour: 0.24,
        fairysBreathPerHour: 1048,
        massOfPureMagicPerHour: 0.16,
        lailasPetalPerHour: 6,
        gatheringExpArtifactPerHour: 0.13,
        gatheringMasteryArtifactPerHour: 0.15,
        gatheringDropRateArtifactPerHour: 0.09,
        lifeExpArtifactPerHour: 0.16,
        lifeMasteryArtifactPerHour: 0.18,
      ),
    ),
  ],
);
