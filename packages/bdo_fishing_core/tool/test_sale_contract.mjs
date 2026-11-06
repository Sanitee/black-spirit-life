// Executes the bundled UI, with an in-memory DOM and no service/profile access.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const script = new URL('../assets/fish_companion/static/app.js', import.meta.url);
const html = fs.readFileSync(new URL('../assets/fish_companion/static/index.html', import.meta.url), 'utf8');
const context = vm.createContext({
  document: { addEventListener() {}, querySelectorAll() { return []; } },
  window: { location: { hash: '' } }, URLSearchParams, Intl, URL, console,
});
vm.runInContext(fs.readFileSync(script, 'utf8'), context);
const run = expression => vm.runInContext(expression, context);
let checks = 0;
function check(expression, expected) {
  assert.equal(run(expression), expected, expression);
  checks++;
}

for (const [rank, level, bonus] of [
  ['Beginner', 1, 5.5], ['Apprentice', 10, 15], ['Skilled', 10, 20],
  ['Professional', 1, 20.5], ['Artisan', 10, 30], ['Master', 30, 45],
  ['Guru', 1, 45.5], ['Guru', 100, 95],
]) check(`bargainBonusFromTradingLevel(${JSON.stringify(rank)}, ${level})`, bonus);
for (const missing of ['null', 'undefined', '""', '"  "', 'NaN', 'Infinity', 'true', '0', '-1', '1.5', '101']) {
  check(`bargainBonusFromTradingLevel('Guru', ${missing})`, 0);
}
check("bargainBonusFromTradingLevel('Master', 31)", 0);
check("bargainBonusFromTradingLevel('Beginner', 11)", 0);
check("bargainBonusFromTradingLevel('toString', 1)", 0);
check("bargainBonusFromTradingLevel(null, 1)", 0);
check('autoFishingDelaySeconds(0)', 180);
check('autoFishingDelaySeconds(30)', 126);
check('autoFishingDelaySeconds(66.67)', 60);
check('autoFishingDelaySeconds(100)', 60);
check('saleProjection(1000, 130, 150, 55)', 5038);
check('saleProjection(1000, 100, 0, 0)', 1000);
run("state.nodes=[{name:'Velia',world:{x:0,z:0}}]");
check("sessionOriginWorld({locationName:'Far from Velia'})", null);
check("sessionOriginWorld({locationName:'Velia'}).exact", false);
run("state.nodes.push({name:'Velia',world:{x:100,z:100}})");
check("sessionOriginWorld({locationName:'Velia'})", null);
run("state.nodes=[{world:{x:0,z:0}}]");
check("sessionOriginWorld({locationName:'Unknown place'})", null);
run("state.nodes=[]");
assert.match(run("offerDestinationOptions('Old town & trader')"), /Old town &amp; trader/);
checks++;
run(`
  globalThis.savedRender=renderSaleOffers;
  renderSaleOffers=()=>{};
  const stub=()=>({classList:{toggle(){},remove(){}},setAttribute(){},dataset:{}});
  for(const key of ['saleTitle','saleOrigin','saleTankValue','saleBargain','saleSoldAt',
    'saleFinalAmount','saleDelete','saleBackdrop']) els[key]=stub();
  state.sessions=[{id:'old',items:[],sale:{destination:'Old town & trader',
    distanceBonusPercent:123,bargainBonusPercent:12.5,finalAmount:12345,
    marketPercent:90,soldAt:'2026-11-01T10:00:00Z'}}];
  openSalePlanner('old');
`);
check("state.salePlanner.offers[0].destination", 'Old town & trader');
check("state.salePlanner.offers[0].distance", 123);
check("els.saleBargain.textContent", '12.5%');
check("els.saleFinalAmount.value", '12345');
run('renderSaleOffers=savedRender');
run(`globalThis.synthetic = {
  id:'synthetic-sale', tradingRank:'Guru', tradingLevel:100,
  items:[{itemId:1,name:'Test fish A',count:2,unitPrice:100},
         {itemId:2,name:'Test fish B',count:3,unitPrice:200}],
  sale:{bargainBonusPercent:50}
};`);
check('saleBargainBonus(synthetic)', 50);
check('saleOfferTotal(synthetic, {distance:100, quotes:{1:130,2:80}})', 2220);
run('synthetic.sale.bargainBonusPercent=0');
check('saleBargainBonus(synthetic)', 0);
check('saleOfferTotal(synthetic, {distance:100, quotes:{1:130,2:80}})', 1480);
run('delete synthetic.sale');
check('saleBargainBonus(synthetic)', 95);
run(`
  globalThis.sent=[]; globalThis.notices=[];
  request=async (url, options)=>{sent.push({url,payload:JSON.parse(options.body)});};
  loadSessions=async()=>{}; closeSalePlanner=()=>{}; renderJournal=()=>{};
  showToast=message=>notices.push(message);
  Object.assign(els, {saleSoldAt:{value:'2026-11-02T12:00'},
    saleFinalAmount:{value:'123456',focus(){}},saleSave:{disabled:false}});
  state.sessions=[synthetic];
  state.salePlanner={sessionId:synthetic.id,selected:0,
    offers:[{destination:'Synthetic destination',distance:100,quotes:{1:130,2:80}}]};
`);
for (const bonus of [0,12.5,50]) {
  run(`synthetic.sale={bargainBonusPercent:${bonus}}`);
  await run('saveRecordedSale()');
  check('sent.at(-1).payload.bargainBonusPercent', bonus);
  check('sent.at(-1).payload.finalAmount', 123456);
  check('els.saleSave.disabled', false);
}
run("sent.length=0; els.saleFinalAmount.value='0'");
await run('saveRecordedSale()');
check('sent.length', 0);
assert.match(html, /before freshness and assuming a successful bargain/);
assert.match(html, /Distance is approximate/);
assert.match(html, /Imperial delivery is not included/);
assert.doesNotMatch(fs.readFileSync(script, 'utf8'), />Fish tank value</);
checks += 4;
console.log(JSON.stringify({syntheticOnly:true,checks,personalDataAccess:false}));
