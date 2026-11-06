// Short reference copy only. These are not Planner recipes or vendor-price rules.
import {additions as novemberAdditions} from './reviewed_item_source_additions_20261102.mjs';
import {additions as novemberVendorAdditions} from './reviewed_vendor_source_additions_20261102.mjs';
import {additions as novemberDawnAdditions} from './reviewed_dawn_source_additions_20261102.mjs';
import {additions as novemberRareFoodAdditions} from './reviewed_rare_food_sources_20261102.mjs';
import {additions as novemberThirdRareFoodAdditions} from './reviewed_rare_food_sources_20261103.mjs';
export const reviewedAt = '2026-11-02';
export const sources = {
  jangdokLocations20261104: {snapshot: 'Current PC item names and bundled house usage 2009; see docs/evidence-followup-20261104.json', scope: 'Jangdok Platform workshops in both Donghae and Seoul; preserve Soy Sauce as a Soybean Paste byproduct. Location hint only, no recipe/yield changes.'},
  kimchiParentReview20261103: {urls: ['https://apps.weingchicken.com/bd/makings/2458', 'https://bdocodex.com/us/recipe/439/?sl=1', 'https://bdocodex.com/kr/item/820801/?sl=1'], scope: 'Korean text and PC recipe output corroborate the exact base/rare direction; current English clause reverses their names. Apprentice 1 base / Skilled 9 rare. No exact proc probability.'},
  eiltonParentReview20261103: {urls: ['https://bdolytics.com/en/crafting/9369%3Aee9ddb3bffa3', 'https://apps.weingchicken.com/bd/makings/2207'], snapshot: 'PC item/recipe metadata extracted 2026-11-02 through October 31', scope: 'Exact 9369/9370 identical-input parent/rare relationship corroborated by PC calculator. Current rare description states Master 1; do not import older Korean 110-minute duration.'},
  novemberRareFoodDescriptions: {snapshot: 'PC descriptions extracted 2026-11-02 through October 31', scope: 'Eight exact normal/rare food identity pairs resolve localized description aliases; rare source and stated skill only, no rate or recipe expansion'},
  novemberSeedDescriptions: {snapshot: 'PC descriptions extracted 2026-11-02 from archives through October 31', scope: '35 exact-identity seed/hypha and ordinary potion additions only; not a refresh of the older complete source registry'},
  novemberVendorDescriptions: {snapshot: 'PC descriptions extracted 2026-11-02 from archives through October 31', scope: 'Star Anise Tea 9306 locations only; raw historical vendor links are not current shop guarantees'},
  crowCoinShop20260521: 'https://www.naeu.playblackdesert.com/News/Notice/Detail?groupContentNo=10081&countryType=en-US',
  patrigioFeather20230719: 'https://blackdesert.pearlabyss.com/TR/en-US/News/Notice/Detail?_boardNo=17267',
  patrigioShopRules: 'https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=17',
  novemberNightShopIdentity: {snapshot: 'PC descriptions and relationships extracted 2026-11-02 through October 31', scope: 'Mythical Feather 757010 and Primordial Crystal 820935 corroborate explicit PC patch additions; no blind native shop import, fixed price or guaranteed availability'},
  dawnMultiplication20260806: 'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10422&countryType=en-US',
  novemberDawnDescriptions: {snapshot: 'PC descriptions extracted 2026-11-02 from archives through October 31', scope: 'Four specialized Essence of Dawn identities and their qualified Heating source; not every accessory grade/yield'},
  farming: 'https://blackdesert.pearlabyss.com/asia/en-us/Game/Wiki?_masterWikiNo=31',
  seeds: 'https://grumpygreen.cricket/alchemy/',
  cropExchange: 'https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=3298',
  workshops: 'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=3855',
  gathering: 'https://blackdesert.pearlabyss.com/TR/en-US/Game/Wiki?_masterWikiNo=128',
  gathering2026: 'https://blackdesert.pearlabyss.com/TR/en-us/News/Notice/Detail?_boardNo=17842',
  morningLightGathering: 'https://www.naeu.playblackdesert.com/en-US/News/Detail?countryType=en-US&groupContentNo=7506',
  morningLightSeeds: 'https://grumpygreen.cricket/seed/',
  seaWaterHeating: 'https://bdocodex.com/us/mrecipe/1430/',
  clientItems: {snapshot: 'PC item metadata, 2026-09-10', sha256: '8998F94AA44A5DD86DC5F67F4CFA73EF1523E3B051B58D8F0F9DC42E592912E5'},
};
export const additions = [...novemberAdditions, ...novemberVendorAdditions, ...novemberDawnAdditions, ...novemberRareFoodAdditions, ...novemberThirdRareFoodAdditions];
// Exact retained application aliases only; never infer an alias or another grade.
export const reviewedNameAliases = [
  {id:5407,name:'Fortune Mushroom',nativeName:'Fortune Teller Mushroom'},
  {id:5426,name:'Big Fortune Mushroom',nativeName:'Big Fortune Teller Mushroom'},
  {id:5470,name:'Special Fortune Mushroom',nativeName:'Special Fortune Teller Mushroom'},
  {id:9741,name:"Griffon's Claw",nativeName:'Griffon Claw'},
];
const add = (id, name, lines, evidence) => additions.push({id, name, lines, evidence});
add(9008,'Sun-Dried Salt',['Processing · Heat Bottle of Sea Water (rare extra)'],['seaWaterHeating','clientItems']);
add(820152,'Millennial Wild Ginseng',['Gather · Gathering minigames (very rare)'],['clientItems']);
for(const [id,name,source] of [[7001,'Wheat','dried thickets or bushes'],[7002,'Barley','dried thickets or bushes'],[7003,'Potato','potato plants'],[7004,'Sweet Potato','thickets or bushes'],[7005,'Corn','corn plants']]) {
  add(id,name,[`Seeds · Gather ${source} by hand or with a hoe (chance)`],['clientItems','farming']);
}
for (const [id,name] of [[820126,'Perilla'],[820117,'Rice'],[820120,'Napa Cabbage'],[820123,'Radish']]) {
  add(id,name,[
    `Gather · ${name} plants in Morning Light (hands or hoe)`,
    "Seeds · Buy normal seeds from Noyoung in Nampo's Moodle Village",
    `Seeds · Gather ${name} plants in Morning Light (chance)`,
  ],['morningLightGathering','morningLightSeeds','clientItems']);
}
for (const [id, name] of [[7301,'Pepper'],[7302,'Garlic'],[7303,'Onion'],[7305,'Hot Pepper']]) {
  add(id, name, [
    'Seeds · Buy normal seeds from Ahr in Calpheon',
    `Exchange · 1 Special ${name} → 4 ${name} at a Seed Vendor`,
  ], ['seeds','cropExchange']);
}
for (const [id,name] of [[7323,'Pepper'],[7324,'Garlic'],[7325,'Onion'],[7327,'Hot Pepper']]) {
  add(id, `High-Quality ${name}`, [
    `Exchange · 1 Special ${name} → 2 High-Quality ${name} at a Seed Vendor`,
  ], ['cropExchange']);
}
for (const [id,name] of [[7304,'Strawberry'],[7306,'Pumpkin'],[7307,'Grape'],[7308,'Sunflower'],[7309,'Olive'],[54001,'Carrot']]) {
  add(id, name, ['Seeds · Buy normal seeds from Ahr in Calpheon'], ['seeds']);
}
add(9073, 'Bean Sprouts', ['Workers · Jangdok Platform (Donghae / Seoul)'], ['workshops','jangdokLocations20261104']);
add(9078, 'Meju', ['Workers · Jangdok Platform (Donghae / Seoul)'], ['workshops','jangdokLocations20261104']);
add(9076, 'Soybean Paste', ['Workers · Jangdok Platform (Donghae / Seoul)'], ['workshops','jangdokLocations20261104']);
add(9075, 'Soy Sauce', ['Workers · Extra from Soybean Paste at a Jangdok Platform (Donghae / Seoul)'], ['workshops','jangdokLocations20261104']);
add(9065, 'Milk', [
  'Gather · Milk cows (10 Energy per try)',
  'Garden · Raise cows with a Haystack',
  "Exchange · 10 Witch's Delicacy → 120 Milk with Liana",
], ['cropExchange','farming','clientItems']);
add(5600, 'Weeds', ['Gather · Pick bushes and thickets by hand'], ['gathering']);
add(5205, 'Fruit of Nature', ['Gather · Plants with a hoe (rare extra)'], ['gathering2026']);
for (const [id,name,quantity] of [[5439,'Wild Grass',30],[4605,'Log',20],[4006,'Rough Stone',12],[5205,'Fruit of Nature',1],[5960,'Trace of Nature',1]]) {
  add(id, name, [`Exchange · 10 Fairy's Breath → ${quantity} ${name} with Dalishain`], ['gathering2026','clientItems']);
}
for (const [id,name,quantity] of [[5301,'Clear Liquid Reagent',200],[4801,'Powder of Darkness',200],[4802,'Powder of Flame',200],[4803,'Powder of Rifts',200],[4804,'Powder of Earth',200],[4805,'Powder of Time',200],[9733,'Shining Powder',5]]) {
  add(id, name, [`Exchange · 10 Mysterious Catalyst → ${quantity} ${name} with Dalishain`], ['clientItems']);
}
add(9213, 'Beer', ["Exchange · 10 Witch's Delicacy → 500 Beer with Liana"], ['clientItems']);
add(9791, 'Essence of Insight', ['Monster drops · Rare extra'], ['clientItems']);
add(9778, 'Thick Turo Blood', ["Monster drops · O'dyllita (rare)"], ['clientItems']);
// Same plant, not a promise that every herb/mushroom has a seed or hypha.
for (const [id,name] of [[5401,'Sunrise Herb'],[5402,'Silver Azalea'],[5403,'Fire Flake Flower'],[5404,'Dry Mane Grass'],[5405,'Silk Honey Grass']]) {
  add(id, name, ['Seeds · Gather the matching herb with a hoe (chance)'], ['seeds','gathering']);
}
