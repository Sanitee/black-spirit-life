import '../../domain/opportunities/exchange_models.dart';

// Additional rewards for the five user-selected currencies. PC client IDs,
// original artwork and sale eligibility checked on 25 September 2026.
const additionalExchangeItems = <int, ExchangeItem>{
  320009: ExchangeItem(
    id: 320009,
    name: "Main Weapon Exchange Coupon",
    iconAsset: 'assets/opportunities/items/320009.webp',
  ),
  320011: ExchangeItem(
    id: 320011,
    name: "Awakening Weapon Exchange Coupon",
    iconAsset: 'assets/opportunities/items/320011.webp',
  ),
  320010: ExchangeItem(
    id: 320010,
    name: "Sub-weapon Exchange Coupon",
    iconAsset: 'assets/opportunities/items/320010.webp',
  ),
  890001: ExchangeItem(
    id: 890001,
    name: "Gold Bar Box",
    iconAsset: 'assets/opportunities/items/890001.webp',
  ),
  45912: ExchangeItem(
    id: 45912,
    name: "[Event] Enhancement Help Kit III",
    iconAsset: 'assets/opportunities/items/45912.webp',
  ),
  761018: ExchangeItem(
    id: 761018,
    name: "Chilling Fragment",
    iconAsset: 'assets/opportunities/items/761018.webp',
  ),
  768160: ExchangeItem(
    id: 768160,
    name: "Sealed Black Magic Crystal",
    iconAsset: 'assets/opportunities/items/768160.webp',
    marketable: true,
    vendorSellPrice: 11800,
  ),
  59858: ExchangeItem(
    id: 59858,
    name: "Resplendent Lightstone of Fire",
    iconAsset: 'assets/opportunities/items/59858.webp',
  ),
  59859: ExchangeItem(
    id: 59859,
    name: "Resplendent Lightstone of Earth",
    iconAsset: 'assets/opportunities/items/59859.webp',
  ),
  59860: ExchangeItem(
    id: 59860,
    name: "Resplendent Lightstone of Wind",
    iconAsset: 'assets/opportunities/items/59860.webp',
  ),
  45107: ExchangeItem(
    id: 45107,
    name: "Essence of Gallantry",
    iconAsset: 'assets/opportunities/items/45107.webp',
  ),
  45105: ExchangeItem(
    id: 45105,
    name: "Essence of Honor",
    iconAsset: 'assets/opportunities/items/45105.webp',
  ),
  45026: ExchangeItem(
    id: 45026,
    name: "Marni's Unstable Fuel",
    iconAsset: 'assets/opportunities/items/45026.webp',
  ),
  820152: ExchangeItem(
    id: 820152,
    name: "Millennial Wild Ginseng",
    iconAsset: 'assets/opportunities/items/820152.webp',
    marketable: true,
  ),
  11017: ExchangeItem(
    id: 11017,
    name: "Dim Tree Spirit's Armor",
    iconAsset: 'assets/opportunities/items/11017.webp',
    marketable: true,
    vendorSellPrice: 54000,
  ),
  752825: ExchangeItem(
    id: 752825,
    name: "[Event] Manos Accessory Box",
    iconAsset: 'assets/opportunities/items/752825.webp',
  ),
  757004: ExchangeItem(
    id: 757004,
    name: "Royal Fern Root",
    iconAsset: 'assets/opportunities/items/757004.webp',
    vendorSellPrice: 10000,
  ),
  757010: ExchangeItem(
    id: 757010,
    name: "Mythical Feather",
    iconAsset: 'assets/opportunities/items/757010.webp',
    marketable: true,
    vendorSellPrice: 100000,
  ),
  59861: ExchangeItem(
    id: 59861,
    name: "Resplendent Lightstone of Flora",
    iconAsset: 'assets/opportunities/items/59861.webp',
  ),
  4917: ExchangeItem(
    id: 4917,
    name: "Forest Fury",
    iconAsset: 'assets/opportunities/items/4917.webp',
    marketable: true,
    vendorSellPrice: 60000,
  ),
  50815: ExchangeItem(
    id: 50815,
    name: "Brilliant Crimson Fire Flower",
    iconAsset: 'assets/opportunities/items/50815.webp',
    vendorSellPrice: 100000,
  ),
  50816: ExchangeItem(
    id: 50816,
    name: "Fruit of Yianaros",
    iconAsset: 'assets/opportunities/items/50816.webp',
    vendorSellPrice: 100000,
  ),
  50817: ExchangeItem(
    id: 50817,
    name: "Mysterious Blue Conch",
    iconAsset: 'assets/opportunities/items/50817.webp',
    vendorSellPrice: 100000,
  ),
  607185: ExchangeItem(
    id: 607185,
    name: "Secret Scroll of Pure Equilibrium",
    iconAsset: 'assets/opportunities/items/607185.webp',
  ),
  289250: ExchangeItem(
    id: 289250,
    name: "Advice of Valks (+350)",
    iconAsset: 'assets/opportunities/items/289250.webp',
  ),
  289200: ExchangeItem(
    id: 289200,
    name: "Advice of Valks (+300)",
    iconAsset: 'assets/opportunities/items/289200.webp',
  ),
  289150: ExchangeItem(
    id: 289150,
    name: "Advice of Valks (+250)",
    iconAsset: 'assets/opportunities/items/289150.webp',
  ),
  289100: ExchangeItem(
    id: 289100,
    name: "Advice of Valks (+200)",
    iconAsset: 'assets/opportunities/items/289100.webp',
  ),
  1000509: ExchangeItem(
    id: 1000509,
    name: "[Title] Field Master",
    iconAsset: 'assets/opportunities/items/1000509.webp',
  ),
  1000510: ExchangeItem(
    id: 1000510,
    name: "[Title] Flame Tower",
    iconAsset: 'assets/opportunities/items/1000510.webp',
  ),
  1000511: ExchangeItem(
    id: 1000511,
    name: "[Title] Hwacha",
    iconAsset: 'assets/opportunities/items/1000511.webp',
  ),
  1000512: ExchangeItem(
    id: 1000512,
    name: "[Title] Cannoneer",
    iconAsset: 'assets/opportunities/items/1000512.webp',
  ),
  1000513: ExchangeItem(
    id: 1000513,
    name: "[Title] Strike Force",
    iconAsset: 'assets/opportunities/items/1000513.webp',
  ),
  45124: ExchangeItem(
    id: 45124,
    name: "Gold Bar Box",
    iconAsset: 'assets/opportunities/items/45124.webp',
  ),
  890003: ExchangeItem(
    id: 890003,
    name: "Gold Bar Box",
    iconAsset: 'assets/opportunities/items/890003.webp',
  ),
  8042: ExchangeItem(
    id: 8042,
    name: "Tears of War",
    iconAsset: 'assets/opportunities/items/8042.webp',
  ),
  4989: ExchangeItem(
    id: 4989,
    name: "Red Essence",
    iconAsset: 'assets/opportunities/items/4989.webp',
  ),
};
