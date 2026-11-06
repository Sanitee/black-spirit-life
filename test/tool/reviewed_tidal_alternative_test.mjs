import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {applyReviewedTidalAlternative} from '../../tool/apply_reviewed_tidal_alternative_20261103.mjs';
const load=()=>JSON.parse(fs.readFileSync('assets/data/app-data.json'));
test('reapplication reproduces exact bundled catalog',()=>{const b=load();assert.deepEqual(applyReviewedTidalAlternative(b),b);});
test('only exact recipe options and source note change',()=>{const b=load();b.processing.items['Deep Blue Tidal Draught'].ingredients[0]={name:'Tidal Draught',qty:4};b.processing.items['Deep Blue Tidal Draught'].sourceNote='Imported from BDO Codex mrecipe 7590. 1 of 2 variants fit this planner recipe; remaining variants stay in import metadata.';const original=structuredClone(b),after=applyReviewedTidalAlternative(b);assert.deepEqual(b,original);assert.deepEqual(after,load());});
test('wrong output or alternative identity fails closed',()=>{for(const n of ['Deep Blue Tidal Draught','Blue Tidal Draught']){const b=load();b.processing.items[n].marketId='1';assert.throws(()=>applyReviewedTidalAlternative(b));}});
test('unknown catalyst or quantity change fails closed',()=>{const b=load();b.processing.items['Deep Blue Tidal Draught'].ingredients[1].qty=2;assert.throws(()=>applyReviewedTidalAlternative(b));const c=load();c.processing.items['Deep Blue Tidal Draught'].ingredients[0].qty=3;assert.throws(()=>applyReviewedTidalAlternative(c));});
