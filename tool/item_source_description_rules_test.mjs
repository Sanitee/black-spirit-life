import test from 'node:test';
import assert from 'node:assert/strict';
import {reviewedDescriptionSources} from './item_source_description_rules.mjs';
const catalog = {cookingSpecialMap: {'Cheese Gratin': {name:'Chewy Cheese Gratin'}}};
const item = (route, name='Chewy Cheese Gratin') => ({name,description:`- <PAColor0xff57f426>How to Obtain<PAOldColor>: ${route}`});
test('rare dish preserves the exact parent and minimum skill', () => {
  assert.deepEqual(reviewedDescriptionSources(item('Slight chance of obtaining Chewy Cheese Gratin when making Cheese Gratin if at least Cooking Professional 3'), catalog), ['Cooking · Make Cheese Gratin (rare extra, Professional 3+)']);
});
test('explicit native extra can use a known recipe without a substitute map', () => {
  assert.deepEqual(reviewedDescriptionSources(item('Slight chance of obtaining Chewy Cheese Gratin when making Cheese Gratin if at least Cooking Professional 3'), {cookingSpecialMap:{},cooking:{items:{'Cheese Gratin':{type:'cooking',ingredients:[{}]}}}}), ['Cooking · Make Cheese Gratin (rare extra, Professional 3+)']);
});
test('unknown output, parent and trailing conditions do not silently pass', () => {
  for (const route of [
    'Slight chance of obtaining Other Gratin when making Cheese Gratin if at least Cooking Professional 3',
    'Slight chance of obtaining Chewy Cheese Gratin when making Mystery Gratin if at least Cooking Professional 3',
    'Slight chance of obtaining Chewy Cheese Gratin when making Cheese Gratin if at least Cooking Professional 3 after a quest',
  ]) assert.deepEqual(reviewedDescriptionSources(item(route), catalog), []);
});
test('farming describes harvest and seed breeding separately', () => {
  assert.deepEqual(reviewedDescriptionSources(item('Farming (seeds via Plant Breeding in a garden)', 'Special Fog Mushroom'), catalog), ['Garden · Grow in a fenced garden', 'Hyphae · Use Plant Breeding in your garden']);
});
test('gathering retains both tools and the level qualification', () => {
  assert.deepEqual(reviewedDescriptionSources(item('Gathering (Fog Mushrooms with bare hands or a hoe, affected by Gathering Level)', 'Big Fog Mushroom'), catalog), ['Gather · Fog Mushrooms (hands or hoe; depends on Gathering level)']);
});
test('unresolved binds and unrelated flavor text never become sources', () => {
  assert.deepEqual(reviewedDescriptionSources({name:'Something',description:'Defeat monsters in Edania'}, catalog), []);
  assert.deepEqual(reviewedDescriptionSources(item('{TextBind:ITEM_SOURCE}'), catalog), []);
});

test('combined native routes preserve exact gathering tools and requirements', () => {
  assert.deepEqual(reviewedDescriptionSources(item('Production (Forest of Plunder), Gathering (Arrow Mushrooms with bare hands or a hoe)','Arrow Mushroom'),catalog),['Gather · Arrow Mushrooms (hands or hoe)']);
  assert.deepEqual(reviewedDescriptionSources(item('Grinding (Insectivore Plant Flower x5 or Insectivore Plant Leaf x5), Gathering (Insectivore Plant with bare hands or a hoe, requires high Gathering Mastery)','Insectivore Plant Powder'),catalog),['Gather · Insectivore Plant (hands or hoe; high Gathering Mastery required)']);
  assert.deepEqual(reviewedDescriptionSources(item('Gathering (Apple Tree with bare hands), purchase via special merchant','Apple'),catalog),['Gather · Apple Tree (by hand)']);
});

test('unknown gathering qualifications are not discarded', () => {
  assert.deepEqual(reviewedDescriptionSources(item('Gathering (Plant with bare hands or a hoe, only during an event)','Plant'),catalog),[]);
  assert.deepEqual(reviewedDescriptionSources(item('Chopping (Timber x5)','Plank'),catalog),[]);
});

test('normal crafting requirement never leaks to a rare output', () => {
  const c={cookingSpecialMap:{},cooking:{items:{Beer:{type:'cooking',ingredients:[{}]},'Cold Draft Beer':{type:'gathered',ingredients:[]}}}};
  const route='Craft via a Cooking Utensil in your residence if at least Cooking Beginner 1 (slight chance of obtaining Cold Draft Beer when making Beer if at least Cooking Skilled 1)';
  assert.deepEqual(reviewedDescriptionSources(item(route,'Beer'),c),['Cooking · Beginner 1+']);
  assert.deepEqual(reviewedDescriptionSources(item(route,'Cold Draft Beer'),c),['Cooking · Make Beer (rare extra, Skilled 1+)']);
});

test('parenthesized rare source retains its higher skill and full conditions', () => {
  const c={cookingSpecialMap:{},cooking:{items:{'Chanterelle Risotto':{type:'cooking',ingredients:[{}]}}}};
  const route='Craft via a Cooking Utensil in your residence if at least Cooking Professional 1 (slight chance of obtaining Aromatic Chanterelle Risotto when making Chanterelle Risotto if at least Cooking Master 1)';
  assert.deepEqual(reviewedDescriptionSources(item(route,'Aromatic Chanterelle Risotto'),c),['Cooking · Make Chanterelle Risotto (rare extra, Master 1+)']);
  for(const invalid of [route+' after a quest',route.replace('Master 1)','Master 1 after a quest)'),route.replace('Chanterelle Risotto if','Other Risotto if')]) {
    assert.deepEqual(reviewedDescriptionSources(item(invalid,'Aromatic Chanterelle Risotto'),c),[]);
  }
});

test('missing if in a complete native clause is accepted without name guessing', () => {
  const c={cookingSpecialMap:{},cooking:{items:{'Chanterelle and Potato Stew':{type:'cooking',ingredients:[{}]}}}};
  const route='Craft via a Cooking Utensil in your residence if at least Cooking Apprentice 6 (slight chance of obtaining Nutritious Chanterelle and Potato Stew when making Chanterelle and Potato Stew at least Cooking Professional 6)';
  assert.deepEqual(reviewedDescriptionSources(item(route,'Nutritious Chanterelle and Potato Stew'),c),['Cooking · Make Chanterelle and Potato Stew (rare extra, Professional 6+)']);
  assert.deepEqual(reviewedDescriptionSources(item(route,'Nutritious Chanterelle Stew'),c),[]);
});

test('reversed White Kimchi text is not turned into an invented rare recipe', () => {
  const c={cookingSpecialMap:{},cooking:{items:{'White Kimchi':{type:'cooking',ingredients:[{}]},'Fresh White Kimchi':{type:'gathered',ingredients:[]}}}};
  const route='Craft via a Cooking Utensil in your residence if at least Cooking Apprentice 1 (slight chance of obtaining White Kimchi when making Fresh White Kimchi if at least Cooking Skilled 9)';
  assert.deepEqual(reviewedDescriptionSources(item(route,'Fresh White Kimchi'),c),[]);
  assert.deepEqual(reviewedDescriptionSources(item(route,'White Kimchi'),c),['Cooking · Apprentice 1+']);
});
