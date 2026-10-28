/// Reviewed exchange facts. These are choices, never simultaneous rewards.
enum ExchangeSaleMode { immediate, listing }

enum ExchangeLimitKind { repeatable, oncePerFamily, weekly, daily }

enum ExchangeAvailability {
  available,
  confirmationNeeded,
  limitReached,
  notEnoughCurrency,
  marketUnknown,
  notEnoughBuyers,
}

class ExchangeSource {
  const ExchangeSource(this.label, this.url);

  final String label;
  final String url;
}

class ExchangeItem {
  const ExchangeItem({
    required this.id,
    required this.name,
    required this.iconAsset,
    this.marketable = false,
    this.vendorSellPrice,
  });

  final int id;
  final String name;
  final String iconAsset;
  final bool marketable;

  /// Verified NPC sale proceeds, not the client's unrelated purchase price.
  final int? vendorSellPrice;
}

class ExchangeReward {
  const ExchangeReward.item(this.item, {this.quantity = 1})
    : utilityName = null,
      utilityIconAsset = null;

  const ExchangeReward.utility(
    this.utilityName, {
    this.quantity = 1,
    this.utilityIconAsset,
  }) : item = null;

  final ExchangeItem? item;
  final String? utilityName;
  final String? utilityIconAsset;
  final int quantity;
  String get name => item?.name ?? utilityName!;
  String? get iconAsset => item?.iconAsset ?? utilityIconAsset;
  bool get isUtility => item == null;
}

class ExchangeLimit {
  const ExchangeLimit.repeatable()
    : kind = ExchangeLimitKind.repeatable,
      maximum = null;

  const ExchangeLimit.oncePerFamily()
    : kind = ExchangeLimitKind.oncePerFamily,
      maximum = 1;

  const ExchangeLimit.family(this.maximum)
    : kind = ExchangeLimitKind.oncePerFamily;

  const ExchangeLimit.weekly(this.maximum) : kind = ExchangeLimitKind.weekly;

  const ExchangeLimit.daily(this.maximum) : kind = ExchangeLimitKind.daily;

  final ExchangeLimitKind kind;
  final int? maximum;

  bool get isRepeatable => kind == ExchangeLimitKind.repeatable;
  String get label => switch (kind) {
    ExchangeLimitKind.repeatable => 'Repeatable',
    ExchangeLimitKind.oncePerFamily =>
      maximum == 1 ? 'Once per family' : 'Up to $maximum per family',
    ExchangeLimitKind.weekly => 'Up to $maximum per week',
    ExchangeLimitKind.daily => 'Up to $maximum per day',
  };
}

class ExchangeRoute {
  const ExchangeRoute({
    required this.id,
    required this.inputCount,
    required this.rewards,
    required this.location,
    this.limit = const ExchangeLimit.repeatable(),
    this.requirements = const [],
    this.notes = const [],
    this.sources = const [],
    this.directVendorSale = false,
    this.rewardContainer,
  });

  final String id;
  final int inputCount;
  final List<ExchangeReward> rewards;
  final String location;
  final ExchangeLimit limit;
  final List<String> requirements;
  final List<String> notes;
  final List<ExchangeSource> sources;

  /// Selling the currency itself; no exchange and no marketplace tax.
  final bool directVendorSale;

  /// The actual exchanged box, when [rewards] are its guaranteed contents.
  /// This is display identity only; never add the closed box to sale proceeds.
  final ExchangeItem? rewardContainer;
}

class ExchangeCurrency {
  const ExchangeCurrency({
    required this.id,
    required this.item,
    required this.sourceActivity,
    required this.routes,
    this.notes = const [],
    this.sources = const [],
    this.legacy = false,
  });

  final String id;
  final ExchangeItem item;
  final String sourceActivity;
  final List<ExchangeRoute> routes;
  final List<String> notes;
  final List<ExchangeSource> sources;
  final bool legacy;
}

class ExchangeRewardQuote {
  const ExchangeRewardQuote({
    required this.reward,
    required this.quantity,
    required this.netProceeds,
    required this.soldQuantity,
    this.vendorSale = false,
  });

  final ExchangeReward reward;
  final int quantity;
  final double? netProceeds;
  final int soldQuantity;
  final bool vendorSale;
  int get remainingQuantity => quantity - soldQuantity;
}

class ExchangeQuote {
  const ExchangeQuote({
    required this.currency,
    required this.route,
    required this.owned,
    required this.possibleExchanges,
    required this.exchanges,
    required this.rewardQuotes,
    required this.availability,
    required this.netProceeds,
    required this.saleMode,
    this.isReference = false,
    this.listingEstimate,
  });

  final ExchangeCurrency currency;
  final ExchangeRoute route;
  final int owned;

  /// Whole exchanges before market-depth, account-limit and quest checks.
  final int possibleExchanges;
  final int exchanges;
  final List<ExchangeRewardQuote> rewardQuotes;
  final ExchangeAvailability availability;
  final double? netProceeds;
  final ExchangeSaleMode saleMode;

  /// A one-exchange comparison, not a claim about the user's owned balance.
  final bool isReference;

  /// Separately valued listing reference when checked buyers cannot cover the
  /// eligible rewards. Original quantities/proceeds still describe bids only.
  final ExchangeQuote? listingEstimate;
  bool get hasListingEstimate => listingEstimate != null;
  ExchangeQuote get displayQuote => listingEstimate ?? this;

  int get consumed => exchanges * route.inputCount;
  int get remainder => owned - consumed;
  bool get hasUnpricedRewards =>
      rewardQuotes.any((reward) => reward.netProceeds == null);
  bool get isRankable =>
      availability == ExchangeAvailability.available &&
      exchanges > 0 &&
      netProceeds != null &&
      !hasUnpricedRewards;
  double? get valuePerCurrency =>
      consumed > 0 && netProceeds != null ? netProceeds! / consumed : null;
  double? get gainOverVendor =>
      netProceeds != null && currency.item.vendorSellPrice != null
      ? netProceeds! - consumed * currency.item.vendorSellPrice!
      : null;
}
