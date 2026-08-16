/// A verified, town-specific worker-lodging expansion allowance.
///
/// The limits describe the standard shop products observed for the town. Each
/// coupon permanently adds one worker-lodging slot. They are product limits,
/// not a record of anything a particular player owns.
final class WorkerLodgingShopTown {
  const WorkerLodgingShopTown({
    required this.townNodeId,
    required this.townName,
    required this.pearlCouponLimit,
    this.loyaltyCouponLimit,
    this.aliases = const <String>{},
  }) : assert(pearlCouponLimit >= 0),
       assert(loyaltyCouponLimit == null || loyaltyCouponLimit >= 0);

  final String townNodeId;
  final String townName;

  /// Maximum purchases of the standard town-specific Pearl coupon.
  final int pearlCouponLimit;

  /// Maximum purchases of the standard town-specific Loyalty coupon.
  ///
  /// `null` means that no town-specific Loyalty product was present in the
  /// submitted shop evidence. It deliberately does not mean a limit of zero.
  final int? loyaltyCouponLimit;

  /// Search and source-data names that differ from [townName].
  final Set<String> aliases;

  /// Slots verified across the standard products visible in the evidence.
  ///
  /// This excludes generic choice boxes and any other event bonus because
  /// those do not belong to a town until the player chooses a destination.
  int get verifiedStandardSlotLimit =>
      pearlCouponLimit + (loyaltyCouponLimit ?? 0);

  bool get hasVerifiedLoyaltyCoupon => loyaltyCouponLimit != null;
}

/// A temporary shop product whose lodging destination is chosen after buying.
final class WorkerLodgingChoicePromotion {
  const WorkerLodgingChoicePromotion({
    required this.id,
    required this.name,
    required this.purchaseLimit,
    required this.slotsPerPurchase,
  }) : assert(purchaseLimit > 0),
       assert(slotsPerPurchase > 0);

  final String id;
  final String name;
  final int purchaseLimit;
  final int slotsPerPurchase;

  /// Choice promotions are never attributed to a town by the catalog.
  bool get requiresPlayerSelectedTown => true;

  int get maximumUnassignedSlots => purchaseLimit * slotsPerPurchase;
}

/// Store-product metadata used to explain and validate bonus worker lodging.
///
/// This catalog intentionally contains no player-owned or player-purchased
/// values. User state belongs in preferences and must be entered or imported
/// separately.
abstract final class WorkerLodgingShopCatalog {
  static const slotsPerTownCoupon = 1;

  static const resplendentWorkerLodgingBox = WorkerLodgingChoicePromotion(
    id: 'resplendent-worker-lodging-choice-box',
    name: 'Choose Your Resplendent Worker\'s Lodging Box',
    purchaseLimit: 2,
    slotsPerPurchase: 1,
  );

  static const towns = <WorkerLodgingShopTown>[
    WorkerLodgingShopTown(
      townNodeId: '301',
      townName: 'Heidel',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1301',
      townName: 'Valencia City',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
      aliases: <String>{'Valencia'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1853',
      townName: 'Yukjo Street',
      pearlCouponLimit: 5,
      aliases: <String>{'Seoul', 'Seoul Yukjo Street'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '604',
      townName: 'Port Epheria',
      pearlCouponLimit: 5,
      aliases: <String>{'Epheria', 'Epheria Port'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1380',
      townName: 'Arehaza',
      pearlCouponLimit: 5,
      aliases: <String>{'Arehaza Town'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1649',
      townName: 'Duvencrune',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1',
      townName: 'Velia',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
    ),
    WorkerLodgingShopTown(
      townNodeId: '61',
      townName: 'Olvia',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '302',
      townName: 'Glish',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '601',
      townName: 'Calpheon City',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
      aliases: <String>{'Calpheon'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '602',
      townName: 'Keplan',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '608',
      townName: 'Trent',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1101',
      townName: 'Altinova',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1141',
      townName: 'Tarif',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1314',
      townName: 'Shakatu',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1319',
      townName: 'Sand Grain Bazaar',
      pearlCouponLimit: 5,
      aliases: <String>{'Sand Grain'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1623',
      townName: 'Grána',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
      aliases: <String>{'Grana', 'GrÃ¡na'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1604',
      townName: 'Old Wisdom Tree',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1691',
      townName: 'O\'draxxia',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
      aliases: <String>{'Odraxxia', 'O’draxxia', 'O’Draxxia', 'O\'Draxxia'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1750',
      townName: 'Eilton',
      pearlCouponLimit: 5,
      loyaltyCouponLimit: 1,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1785',
      townName: 'Nampo\'s Moodle Village',
      pearlCouponLimit: 5,
      aliases: <String>{'Moodle Village', 'Nampo Moodle Village'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1781',
      townName: 'Dalbeol Village',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1795',
      townName: 'Nopsae\'s Byeot County',
      pearlCouponLimit: 5,
      aliases: <String>{'Byeot County', 'Nopsae Byeot County'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '2001',
      townName: 'Hakinza Sanctuary',
      pearlCouponLimit: 5,
      aliases: <String>{'Hakinza'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1834',
      townName: 'Asparkan',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1843',
      townName: 'Muzgar',
      pearlCouponLimit: 5,
    ),
    WorkerLodgingShopTown(
      townNodeId: '1857',
      townName: 'Godu Village',
      pearlCouponLimit: 5,
      aliases: <String>{'Godu'},
    ),
    WorkerLodgingShopTown(
      townNodeId: '1858',
      townName: 'Bukpo',
      pearlCouponLimit: 5,
    ),
  ];

  static final Map<String, WorkerLodgingShopTown> townsByNodeId =
      Map<String, WorkerLodgingShopTown>.unmodifiable(
        <String, WorkerLodgingShopTown>{
          for (final town in towns) town.townNodeId: town,
        },
      );

  static final Map<String, WorkerLodgingShopTown> _townsByNormalizedName =
      Map<String, WorkerLodgingShopTown>.unmodifiable(
        <String, WorkerLodgingShopTown>{
          for (final town in towns)
            for (final name in <String>{town.townName, ...town.aliases})
              _normalizeTownName(name): town,
        },
      );

  static WorkerLodgingShopTown? findTown(String nameOrNodeId) {
    final query = nameOrNodeId.trim();
    if (query.isEmpty) return null;
    return townsByNodeId[query] ??
        _townsByNormalizedName[_normalizeTownName(query)];
  }

  static String _normalizeTownName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('’', '')
        .replaceAll('\'', '')
        .replaceAll(RegExp('[^a-z0-9]+'), '');
  }
}
