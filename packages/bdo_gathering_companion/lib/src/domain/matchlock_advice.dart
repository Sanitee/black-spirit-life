/// Equipment advice only: never feed these examples into the calculator.
class MatchlockAdviceSource {
  const MatchlockAdviceSource({required this.label, required this.url});
  final String label, url;
}

class MatchlockAdviceEntry {
  const MatchlockAdviceEntry({
    required this.id,
    required this.name,
    required this.icon,
    required this.benefit,
    required this.count,
    required this.notes,
    required this.sources,
  });
  final String id, name, icon, benefit;
  final int count;
  final List<String> notes;
  final List<MatchlockAdviceSource> sources;
}

class MatchlockAdviceSection {
  const MatchlockAdviceSection({required this.title, required this.lines});
  final String title;
  final List<String> lines;
}

const matchlockCommunitySource = MatchlockAdviceSource(
  label: 'Hunter’s example setup · 7 Sep 2026',
  url:
      'https://www.reddit.com/r/blackdesertonline/comments/1w9zhk1/guru_46_hunter_these_are_all_the_additional/',
);

const _lomlCrystals = MatchlockAdviceSource(
  label: 'Pearl Abyss · Morning Light crystals',
  url:
      'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=3855',
);

const matchlockCrystalAdvice = <MatchlockAdviceEntry>[
  MatchlockAdviceEntry(
    id: '15672',
    name: 'Corrupted Magic Crystal',
    icon: 'assets/icons/items/15672.webp',
    benefit: '+22% critical hit damage with two',
    count: 2,
    notes: [
      '+10% each, plus the +2% two-crystal bonus.',
      'Both use the Extra Damage group. Don’t add another full set from that group.',
      'This is a damage bonus on critical hits, not 22% more total DPS.',
    ],
    sources: [
      matchlockCommunitySource,
      MatchlockAdviceSource(
        label: 'Pearl Abyss · Corrupted crystal effects',
        url:
            'https://blackdesert.pearlabyss.com/TR/en-US/News/Notice/Detail?_boardNo=18479',
      ),
    ],
  ),
  MatchlockAdviceEntry(
    id: '15257',
    name: 'Crystal of Precise Destruction',
    icon: 'assets/icons/items/15257.webp',
    benefit: '+3 critical hit levels',
    count: 1,
    notes: [
      'Simple Cron Meal adds the other two levels.',
      'Skip this if your equipped gear and buffs already give Critical Hit 5.',
      'Levels are not percentage points of critical chance.',
    ],
    sources: [
      MatchlockAdviceSource(
        label: 'Pearl Abyss · Precise Destruction',
        url:
            'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=6407',
      ),
      matchlockCommunitySource,
    ],
  ),
  MatchlockAdviceEntry(
    id: '15256',
    name: 'Crystal of Brutal Decimation',
    icon: 'assets/icons/items/15256.webp',
    benefit: '+2% back attack damage with two',
    count: 2,
    notes: [
      '+1% each. Helps when you shoot from behind.',
      'Two is the Decimation-group limit; upgraded versions share that limit.',
    ],
    sources: [_lomlCrystals, matchlockCommunitySource],
  ),
  MatchlockAdviceEntry(
    id: '15690',
    name: "Glorious Crystal of Gallantry - Ah'krad",
    icon: 'assets/icons/items/15690.webp',
    benefit: '+2% attack speed with two',
    count: 2,
    notes: [
      '+1% each. This is separate from the five Attack Speed levels.',
      'Use compatible unlocked slots; this is not a complete crystal preset.',
    ],
    sources: [
      MatchlockAdviceSource(
        label: 'Pearl Abyss · Glorious crystals',
        url:
            'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=2598',
      ),
      matchlockCommunitySource,
    ],
  ),
  MatchlockAdviceEntry(
    id: '15736',
    name: "Girin's Tear",
    icon: 'assets/icons/items/15736.webp',
    benefit: '+1% special attack damage',
    count: 1,
    notes: [
      'Also gives +3% all resistance.',
      'Use one Primordial crystal, not several different tears together.',
      'An optional upgrade, not something you need before starting.',
    ],
    sources: [_lomlCrystals, matchlockCommunitySource],
  ),
];

const matchlockDamageSections = <MatchlockAdviceSection>[
  MatchlockAdviceSection(
    title: 'Start here',
    lines: [
      'Aim for Attack Speed 5 and Critical Hit 5 with your matchlock out.',
      'Shoot from behind when you can. Percentage bonuses are separate from ability levels.',
    ],
  ),
  MatchlockAdviceSection(
    title: 'Food',
    lines: [
      'Simple Cron Meal: +2 Attack Speed and +2 Critical Hit.',
      'Also gives +5% critical hit damage and +5% back attack damage.',
    ],
  ),
  MatchlockAdviceSection(
    title: 'Extra buffs',
    lines: [
      'The hunter’s damage options: Giant’s, Harmony or Frenzy Draught, plus Perfume of Deep Sea.',
      'Pick one draught. Verdure perfume and Viridian Draught are the mastery, EXP and weight option instead.',
    ],
  ),
  MatchlockAdviceSection(
    title: 'Lightstones',
    lines: [
      'Deathblow: Predation ×2 + Blade ×2 for critical chance. Amplified is an optional upgrade.',
      'Blink of an Eye gives the reload bonus—not Margahan’s Artifact on its own. It no longer gives Attack Speed or Critical Hit levels.',
    ],
  ),
  MatchlockAdviceSection(
    title: 'Gear you already own',
    lines: [
      'Check weapons, reforges and accessory cups for critical chance, critical/back damage and special attack damage.',
      'Sovereign gear is optional. Totals depend on your actual gear; HP and resistance are not damage bonuses.',
    ],
  ),
  MatchlockAdviceSection(
    title: 'Before spending silver',
    lines: [
      'This is one hunter’s setup, not a build for every class. Crystals can break on death.',
      'Class buffs and Black Spirit’s Rage change the result. The post’s Shai and Archer numbers won’t fit everyone.',
    ],
  ),
  MatchlockAdviceSection(
    title: 'Speed reports · 8 Sep 2026',
    lines: [
      'Players have reported issues with Vell’s Heart attack speed and matchlock reload speed.',
      'We haven’t verified a fix. Hold off on buying gear just for these speed bonuses.',
    ],
  ),
];

const matchlockAdviceSources = <MatchlockAdviceSource>[
  MatchlockAdviceSource(
    label: 'Pearl Abyss · Hunting guide',
    url: 'https://www.sa.playblackdesert.com/pt-br/Wiki?wikiNo=74',
  ),
  MatchlockAdviceSource(
    label: 'Pearl Abyss · Gear & lightstone changes',
    url:
        'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19773',
  ),
  MatchlockAdviceSource(
    label: 'Pearl Abyss · Lightstone combinations',
    url: 'https://www.sa.playblackdesert.com/pt-br/Wiki?wikiNo=239',
  ),
  MatchlockAdviceSource(
    label: 'Pearl Abyss · Simple Cron Meal change',
    url:
        'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=7955',
  ),
  MatchlockAdviceSource(
    label: 'Pearl Abyss · Reforge upgrades',
    url:
        'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19693',
  ),
  matchlockCommunitySource,
];
