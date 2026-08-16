enum CraftMode {
  alchemy('alchemy', 'Alchemy'),
  cooking('cooking', 'Cooking'),
  processing('processing', 'Processing');

  const CraftMode(this.key, this.label);

  final String key;
  final String label;
}
