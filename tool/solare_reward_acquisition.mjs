// Rank-limited acquisition references, never production or currency recipes.
export function applySolareRewardAcquisition(info) {
  for (const [name, itemId, quantity] of [
    ['Sturdy Forest Tread', 820022, 20],
    ['Perfume of Envy', 1411, 30],
    ['Perfume of Tenacity', 1413, 30],
  ]) {
    const existing = info[name];
    const reward = {
      kind: 'season_reward',
      summary: `Receive ${quantity} from the Glorious Solare Box for finishing an Arena of Solare ranked season in the Top 100.`,
      availability: 'season-rank-limited',
      confidence: 'high',
      sources: [
        {
          title: 'Official NA/EU October 15, 2026 Solare rewards',
          url: 'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10699',
          supports: ['reward-item', 'quantity', 'rank-requirement'],
        },
        {
          title: 'Official Asia October 15, 2026 Solare rewards',
          url: 'https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=19924',
          supports: ['reward-item', 'quantity', 'rank-requirement'],
        },
      ],
    };
    info[name] = {
      ...existing,
      canonicalName: name,
      itemId,
      status: 'reviewed',
      reviewedAt: '2026-10-15',
      routes: [reward, ...(existing?.routes ?? []).filter(route =>
        !(route.kind === 'season_reward' && route.summary.includes('Glorious Solare Box')))],
    };
  }
  return info;
}
