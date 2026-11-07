// Actual bundled UI, in-memory synthetic DOM/state; no app, service or journal.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const context = vm.createContext({document:{addEventListener(){},querySelectorAll(){return [];}},
  window:{location:{hash:''}}, URLSearchParams,Intl,URL,console,CSS:{escape:x=>x}});
vm.runInContext(fs.readFileSync(new URL('../assets/fish_companion/static/app.js',import.meta.url),'utf8'),context);
const run = expression => vm.runInContext(expression,context);
let checks=0;
function equal(expression, expected) {assert.equal(run(expression),expected,expression);checks++;}
function includes(expression, text) {assert.ok(run(expression).includes(text),expression);checks++;}
run(`
  globalThis.mixed={id:'test',method:'rod',locationName:'Synthetic water',zoneName:'Synthetic table',
    caughtAt:'2026-11-02T12:00:00Z',zoneRgb:123,style:'active',equipment:'rod',durationMinutes:60,
    catches:[{itemId:1,name:'Known fish',count:2,price:100,grade:'green'},
             {itemId:2,name:'Unknown fish',count:3,price:0,grade:'green'}]};
  globalThis.node=()=>({innerHTML:'',textContent:'',title:'',value:'',dataset:{},
    classList:{toggle(){},add(){},remove(){}},querySelector(){return null;},
    querySelectorAll(){return [];},setAttribute(){},addEventListener(){}});
  for(const key of ['reviewEmpty','reviewContent','reviewCount','reviewValue','reviewCoverage',
    'reviewConfidence','recognizedFish','journalStatusField','journalSummary','journalList',
    'saleOffers','saleChosenSummary','saleFinalAmount','statsList','statsDetail']) els[key]=node();
  for(const key of ['statsProfile','statsStyle','statsEquipment','statsMastery','statsResource'])
    els[key]={value:'all'};
  state.method.stats='rod';state.sessions=[mixed];state.review={catches:mixed.catches};
  state.salePlanner={sessionId:'test',selected:0,offers:[{destination:'Test trader',distance:0,quotes:{}}]};
`);
equal('fishValueSummary([]).total',0);
equal('fishValueSummary(mixed.catches).total',null);
equal('fishValueSummary(mixed.catches).knownSubtotal',200);
equal('fishValueSummary(mixed.catches).unknownFish',3);
equal('sessionValue(mixed)',200); // Explicit legacy subtotal persistence contract.
equal('totalReviewValue()',null);
equal('saleOfferTotal(mixed,state.salePlanner.offers[0])',null);
equal('saleItemBaseValue(mixed.catches[1])',null);
equal('saleItemBaseValue({count:0,price:0})',0);
for(const price of ['null','undefined','NaN','Infinity','-1','0','""']) {
  equal(`fishValueSummary([{count:1,price:${price}}]).total`,null);
}
equal('fishValueSummary([{count:2,price:100},{count:3,price:200}]).total',800);
run('state.fishById.set(2,{price:999})');
equal('sessionCatches({items:[{itemId:2,count:1,price:null}]})[0].price',0);
equal('sessionCatches({items:[{itemId:2,count:1,unitPrice:null}]})[0].price',0);
equal('sessionCatches({items:[{itemId:2,count:1}]})[0].price',999);
run('renderReview()');
equal('els.reviewValue.textContent','Unknown');
equal('els.reviewValue.title','3 fish without prices');
equal('els.reviewCount.textContent','5');
run('renderJournal()');
includes('els.journalSummary.innerHTML','3 fish without prices');
includes('els.journalList.innerHTML','3 fish without prices');
assert.doesNotMatch(run('els.journalList.innerHTML'),/title="200 silver"/);checks++;
run('renderSaleOffers()');
includes('els.saleOffers.innerHTML','price unknown');
includes('els.saleChosenSummary.innerHTML','incomplete fish prices');
equal('buildPersonalStats()[0].valuePer100',null);
equal('buildPersonalStats()[0].fishPerHour',5);
equal('buildPersonalStats()[0].totalFish',5);
run('renderStats()');
includes('els.statsList.innerHTML','Base value / 100 · incomplete');
// Simulate existing rendered sale cells so ranking and individual totals are checked.
run(`
  globalThis.cells=new Map();
  els.saleOffers.querySelector=selector=>{if(!cells.has(selector))cells.set(selector,node());return cells.get(selector);};
  updateSaleDecisionTotals();
`);
equal('cells.get(\'[data-sale-total="0"]\').textContent','—');
equal('cells.get(\'[data-sale-rank="0"]\').textContent','Price unknown');
equal('cells.get(\'[data-sale-item-total="0:2"]\').textContent','—');
equal('cells.get(\'[data-sale-item-total="0:1"]\').textContent','200');
run('els.saleFinalAmount.value="123456";renderSaleChosenSummary()');
includes('els.saleChosenSummary.innerHTML','actual silver');
includes('els.saleChosenSummary.innerHTML',run('silver(123456)'));
run('mixed.sale={finalAmount:123456,soldAt:"2026-11-02T12:00:00Z"};renderJournal()');
includes('els.journalList.innerHTML','123.456 silver');
// Resolving only the test price restores complete estimates, not counts or actuals.
run('mixed.catches[1].price=200');
equal('totalReviewValue()',800);
equal('saleOfferTotal(mixed,{distance:0,quotes:{}})',800);
equal('buildPersonalStats()[0].valuePer100',16000);
equal('mixed.sale.finalAmount',123456);
run('updateSaleDecisionTotals()');
equal('cells.get(\'[data-sale-rank="0"]\').textContent','Highest estimate');
console.log(JSON.stringify({syntheticOnly:true,checks,personalDataAccess:false}));
