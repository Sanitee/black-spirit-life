// PC NA/EU February 28, 2024 boss-material simplification, notice6665.
// Generated from the explicitly reviewed obsolete identity blocks only.
// docs/reviewed-boss-material-simplification.json preserves the evidence.
// Do not rewrite old saves, infer conversion ratios, or consume equipment.

const supersededBossCrystalsById = <String, String>{
  '8905': 'Concentrated Offin Tett Crystal',
  '8906': 'Concentrated Karanda Crystal',
  '8907': 'Concentrated Nouver Crystal',
  '8908': 'Concentrated Kutum Crystal',
  '8909': 'Concentrated Giath Crystal',
  '8910': 'Concentrated Griffon Crystal',
  '8911': 'Concentrated Dim Tree Spirit Crystal',
  '8912': 'Concentrated Red Nose Crystal',
  '8913': 'Concentrated Bheg Crystal',
  '8914': 'Concentrated Leebur Crystal',
  '8915': 'Concentrated Muskan Crystal',
  '8916': 'Concentrated Urugon Crystal',
};

const supersededBossAurasById = <String, String>{
  '8918': 'Concentrated Offin Tett\'s Aura',
  '8919': 'Concentrated Karanda\'s Aura',
  '8920': 'Concentrated Nouver\'s Aura',
  '8921': 'Concentrated Kutum\'s Aura',
  '8922': 'Concentrated Giath\'s Aura',
  '8923': 'Concentrated Griffon\'s Aura',
  '8924': 'Concentrated Dim Tree Spirit\'s Aura',
  '8925': 'Concentrated Red Nose\'s Aura',
  '8926': 'Concentrated Bheg\'s Aura',
  '8927': 'Concentrated Leebur\'s Aura',
  '8928': 'Concentrated Muskan\'s Aura',
  '8929': 'Concentrated Urugon\'s Aura',
};

const supersededLatentAurasById = <String, String>{
  '42436': 'Nouver\'s Latent Aura',
  '42437': 'Karanda\'s Latent Aura',
  '42450': 'Kutum\'s Latent Aura',
  '42495': 'Offin Tett\'s Light Fragment',
  '66111': 'Giath\'s Latent Aura',
  '66112': 'Griffon\'s Latent Aura',
  '66113': 'Dim Tree Spirit\'s Latent Aura',
  '66114': 'Red Nose\'s Latent Aura',
  '66115': 'Bheg\'s Latent Aura',
  '66116': 'Leebur\'s Latent Aura',
  '66117': 'Muskan\'s Latent Aura',
  '66118': 'Urugon\'s Latent Aura',
};

const supersededWeaponReformStonesById = <String, String>{
  '8806': 'Resplendent Offin Tett\'s Radiant Main Weapon Reform Stone I',
  '8807': 'Resplendent Offin Tett\'s Radiant Main Weapon Reform Stone II',
  '8808': 'Resplendent Offin Tett\'s Radiant Main Weapon Reform Stone III',
  '8809': 'Resplendent Offin Tett\'s Radiant Main Weapon Reform Stone IV',
  '8810': 'Resplendent Offin Tett\'s Radiant Main Weapon Reform Stone V',
  '8811': 'Resplendent Nouver Sub-weapon Reform Stone I',
  '8812': 'Resplendent Nouver Sub-weapon Reform Stone II',
  '8813': 'Resplendent Nouver Sub-weapon Reform Stone III',
  '8814': 'Resplendent Nouver Sub-weapon Reform Stone IV',
  '8815': 'Resplendent Nouver Sub-weapon Reform Stone V',
  '8816': 'Resplendent Kutum Sub-weapon Reform Stone I',
  '8817': 'Resplendent Kutum Sub-weapon Reform Stone II',
  '8818': 'Resplendent Kutum Sub-weapon Reform Stone III',
  '8819': 'Resplendent Kutum Sub-weapon Reform Stone IV',
  '8820': 'Resplendent Kutum Sub-weapon Reform Stone V',
  '8821': 'Resplendent Dandelion Awakening Weapon Reform Stone I',
  '8822': 'Resplendent Dandelion Awakening Weapon Reform Stone II',
  '8823': 'Resplendent Dandelion Awakening Weapon Reform Stone III',
  '8824': 'Resplendent Dandelion Awakening Weapon Reform Stone IV',
  '8825': 'Resplendent Dandelion Awakening Weapon Reform Stone V',
};

const supersededArmorReformStonesById = <String, String>{
  '8831': 'Resplendent Griffon\'s Helmet Reform Stone I',
  '8832': 'Resplendent Griffon\'s Helmet Reform Stone II',
  '8833': 'Resplendent Griffon\'s Helmet Reform Stone III',
  '8834': 'Resplendent Griffon\'s Helmet Reform Stone IV',
  '8835': 'Resplendent Griffon\'s Helmet Reform Stone V',
  '8836': 'Resplendent Dim Tree Spirit\'s Armor Reform Stone I',
  '8837': 'Resplendent Dim Tree Spirit\'s Armor Reform Stone II',
  '8838': 'Resplendent Dim Tree Spirit\'s Armor Reform Stone III',
  '8839': 'Resplendent Dim Tree Spirit\'s Armor Reform Stone IV',
  '8840': 'Resplendent Dim Tree Spirit\'s Armor Reform Stone V',
  '8841': 'Resplendent Red Nose\'s Armor Reform Stone I',
  '8842': 'Resplendent Red Nose\'s Armor Reform Stone II',
  '8843': 'Resplendent Red Nose\'s Armor Reform Stone III',
  '8844': 'Resplendent Red Nose\'s Armor Reform Stone IV',
  '8845': 'Resplendent Red Nose\'s Armor Reform Stone V',
  '8846': 'Resplendent Bheg\'s Gloves Reform Stone I',
  '8847': 'Resplendent Bheg\'s Gloves Reform Stone II',
  '8848': 'Resplendent Bheg\'s Gloves Reform Stone III',
  '8849': 'Resplendent Bheg\'s Gloves Reform Stone IV',
  '8850': 'Resplendent Bheg\'s Gloves Reform Stone V',
  '8851': 'Resplendent Leebur\'s Gloves Reform Stone I',
  '8852': 'Resplendent Leebur\'s Gloves Reform Stone II',
  '8853': 'Resplendent Leebur\'s Gloves Reform Stone III',
  '8854': 'Resplendent Leebur\'s Gloves Reform Stone IV',
  '8855': 'Resplendent Leebur\'s Gloves Reform Stone V',
  '8856': 'Resplendent Muskan\'s Shoes Reform Stone I',
  '8857': 'Resplendent Muskan\'s Shoes Reform Stone II',
  '8858': 'Resplendent Muskan\'s Shoes Reform Stone III',
  '8859': 'Resplendent Muskan\'s Shoes Reform Stone IV',
  '8860': 'Resplendent Muskan\'s Shoes Reform Stone V',
  '8861': 'Resplendent Urugon\'s Shoes Reform Stone I',
  '8862': 'Resplendent Urugon\'s Shoes Reform Stone II',
  '8863': 'Resplendent Urugon\'s Shoes Reform Stone III',
  '8864': 'Resplendent Urugon\'s Shoes Reform Stone IV',
  '8865': 'Resplendent Urugon\'s Shoes Reform Stone V',
};

const supersededBossMaterialsById = <String, String>{
  ...supersededBossCrystalsById,
  ...supersededBossAurasById,
  ...supersededLatentAurasById,
  ...supersededWeaponReformStonesById,
  ...supersededArmorReformStonesById,
};

String? bossMaterialReplacementFor(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  final id = numeric != null && numeric > 0
      ? '$numeric'
      : supersededBossMaterialsById.entries
            .where((e) => e.value.toLowerCase() == name.trim().toLowerCase())
            .firstOrNull
            ?.key;
  if (id == null) return null;
  if (supersededBossCrystalsById.containsKey(id)) {
    return 'Concentrated Boss Crystal';
  }
  if (supersededBossAurasById.containsKey(id)) return 'Contained Boss Aura';
  if (supersededLatentAurasById.containsKey(id)) return 'Latent Boss Aura';
  final weapon = supersededWeaponReformStonesById[id];
  final armor = supersededArmorReformStonesById[id];
  final original = weapon ?? armor;
  if (original == null) return null;
  final rank = original.split(' ').last;
  return 'Resplendent Boss ${weapon != null ? 'Weapon' : 'Armor'} Reform Stone $rank';
}
