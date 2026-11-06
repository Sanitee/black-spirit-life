// Real bundled Fish HTML/service, isolated scratch state, headless browser.
// Usage: node tool/test_fish_search.mjs <playwright module> <FishHost.exe> <evidence directory> [public catalog fixture]
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const payload = path.join(root, 'assets/fish_companion');
const { chromium } = await import(pathToFileURL(path.resolve(process.argv[2])).href);
const helper = path.resolve(process.argv[3]);
const evidence = path.resolve(process.argv[4]);
await fs.mkdir(evidence, { recursive: true });
const scratch = await fs.mkdtemp(path.join(os.tmpdir(), 'bsl-fish-search-'));
const app = path.join(scratch, 'app');
for (const name of ['static', 'backend', 'recognizer', 'data']) {
  await fs.cp(path.join(payload, name), path.join(app, name), { recursive: true });
}
let nonFishIds = [];
if (process.argv[5]) {
  const fixture = JSON.parse(await fs.readFile(path.resolve(process.argv[5]), 'utf8'));
  assert(Array.isArray(fixture.fish), 'Expected public catalog fixture');
  nonFishIds = fixture.fish.filter(row => row.catalog_kind === 'item').map(row => row.item_id);
  assert(nonFishIds.length > 0, 'Mixed-catalog compatibility fixture must include other loot');
  await fs.writeFile(path.join(app, 'data/cache/fish.json'), JSON.stringify(fixture));
}
const server = net.createServer().listen(0, '127.0.0.1');
await once(server, 'listening');
const port = server.address().port;
await new Promise(resolve => server.close(resolve));
const token = crypto.randomBytes(24).toString('hex');
const origin = `http://127.0.0.1:${port}`;
const service = spawn(helper, ['--owner-pid', String(process.pid), '--',
  path.join(payload, 'runtime/fish_companion_service.exe'), '--root', app,
  '--personal-data-root', path.join(scratch, 'personal'),
  '--reference-cache-root', path.join(scratch, 'reference-cache'),
  '--port', String(port), '--parent-pid', String(process.pid), '--api-token', token],
{ windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
let stopped = false;
service.once('close', () => { stopped = true; });
const report = { syntheticOnly: true, scratch, checks: [], errors: [] };
const check = (label) => { report.checks.push(label); console.log(label); };
let browser;
try {
  const deadline = Date.now() + 30000;
  let ready = false;
  while (Date.now() < deadline && !stopped) {
    try {
      const response = await fetch(`${origin}/api/health`, { headers: { 'X-BSL-API-Token': token }, signal: AbortSignal.timeout(1000) });
      if (response.ok) { ready = true; break; }
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  assert(ready, 'Synthetic Fish service failed to start');
  if (nonFishIds.length) {
    const response = await fetch(`${origin}/api/bootstrap`, {headers:{'X-BSL-API-Token':token}});
    assert(response.ok);
    const bootstrap = await response.json();
    assert.equal(bootstrap.fish.length, 303);
    assert(!bootstrap.fish.some(row => nonFishIds.includes(row.itemId)));
    assert(bootstrap.zones.some(zone => zone.items.some(row => row.itemId === 40218 && row.isFish === false)));
    check('compiled service accepts mixed current catalog: 303 fish; non-fish loot stays in its own table rows');
  }
  browser = await chromium.launch({ channel: 'msedge', headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 }, deviceScaleFactor: 1 });
  // No third-party source refresh or unrelated requests during the visual test.
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.origin !== origin) return route.abort();
    if (url.pathname === '/api/background-refresh') return route.fulfill({ json: { started: false } });
    return route.continue();
  });
  const page = await context.newPage();
  page.on('pageerror', error => report.errors.push(String(error)));
  await page.goto(`${origin}/#apiToken=${token}`);
  await page.waitForSelector('#app:not(.is-hidden)');
  await page.waitForFunction(() => !document.querySelector('#boot'));
  const input = page.locator('#mapSearch');
  const options = page.locator('#mapFishSuggestions [role=option]');
  const popup = page.locator('#mapFishSuggestions');
  const initialMap = await page.locator('#mapViewport').boundingBox();
  assert.equal(await input.inputValue(), '');
  assert.equal(await input.getAttribute('list'), null);
  await input.fill('Cloakin');
  await options.first().waitFor();
  assert.deepEqual(await options.allTextContents(), ['Cloaking Shark']);
  assert.equal(await options.locator('small, [title]').count(), 0);
  await page.waitForFunction(() => [...document.querySelectorAll('#mapFishSuggestions img')].every(img => img.complete && img.naturalWidth > 0));
  assert.match(await options.locator('img').getAttribute('src'), /\/icon\/820995\.webp$/);
  assert.equal(await input.getAttribute('aria-expanded'), 'true');
  assert.deepEqual(await page.locator('#mapViewport').boundingBox(), initialMap);
  const style = await input.evaluate(el => {
    const s = getComputedStyle(el);
    return { border: s.borderWidth, shadow: s.boxShadow, outline: s.outlineStyle, background: s.backgroundColor };
  });
  assert.deepEqual(style, { border: '0px', shadow: 'none', outline: 'none', background: 'rgba(0, 0, 0, 0)' });
  await page.screenshot({ path: path.join(evidence, 'fish-search-full.png') });
  await page.locator('#mapTools').screenshot({ path: path.join(evidence, 'fish-search-detail.png') });
  check('single search frame; name and real Cloaking Shark artwork only; map geometry stable');

  await options.first().click();
  assert.equal(await input.inputValue(), 'Cloaking Shark');
  assert.equal(await popup.isVisible(), false);
  const pointerResults = await page.locator('#mapResults').textContent();
  await input.fill('Cloakin');
  await input.press('ArrowDown');
  assert.equal(await options.first().getAttribute('aria-selected'), 'true');
  assert.equal(await input.getAttribute('aria-activedescendant'), 'map-fish-option-0');
  await input.press('Enter');
  assert.equal(await input.inputValue(), 'Cloaking Shark');
  assert.equal(await page.locator('#mapResults').textContent(), pointerResults);
  assert.equal(await popup.isVisible(), false);
  check('mouse and keyboard choose the same fish and preserve existing table filtering');

  await input.fill('shark');
  assert((await options.count()) > 1);
  await input.press('ArrowUp');
  assert.equal(await options.last().getAttribute('aria-selected'), 'true');
  await input.press('ArrowDown');
  assert.equal(await options.first().getAttribute('aria-selected'), 'true');
  await input.press('Escape');
  assert.equal(await input.inputValue(), 'shark');
  assert.equal(await popup.isVisible(), false);
  await input.press('ArrowDown');
  assert.equal(await popup.isVisible(), true);
  await input.press('Tab');
  assert.equal(await popup.isVisible(), false);
  await input.click();
  await page.locator('.map-finder-title').click();
  assert.equal(await popup.isVisible(), false);
  check('arrows wrap; Escape, Tab, and outside click dismiss without changing query');

  await input.fill('820995');
  assert.deepEqual(await options.allTextContents(), ['Cloaking Shark']);
  await input.fill('Velia');
  await input.press('Enter');
  assert.equal(await input.inputValue(), 'Velia');
  assert.match(await page.locator('#mapResults').textContent(), /Velia/);
  await input.fill('no-such-fish-000');
  assert.equal(await popup.isVisible(), false);
  await input.fill('');
  assert.equal(await popup.isVisible(), false);
  check('item ID lookup and free-text place search remain; empty/no-match has no popup');

  await input.fill('a');
  assert((await options.count()) > 30);
  await popup.hover();
  const mapBeforeWheel = await page.locator('#mapViewport').boundingBox();
  await page.mouse.wheel(0, 500);
  await page.waitForTimeout(150);
  assert((await popup.evaluate(el => el.scrollTop)) > 0);
  assert.deepEqual(await page.locator('#mapViewport').boundingBox(), mapBeforeWheel);
  await input.press('ArrowUp');
  const lastBox = await options.last().boundingBox();
  const popupBox = await popup.boundingBox();
  assert(lastBox.y + lastBox.height <= popupBox.y + popupBox.height + 1);
  check('long suggestion list scrolls; keyboard reaches last option without moving map');

  for (const [width, height, zoom] of [[960, 600, 1], [1200, 752, 1.5], [1200, 752, 2]]) {
    await page.setViewportSize({ width, height });
    await page.evaluate(z => { document.documentElement.style.zoom = z; }, zoom);
    await input.fill('shark');
    await options.first().waitFor();
    assert.equal(await popup.evaluate(el => el.scrollTop), 0);
    const box = await popup.boundingBox();
    const pane = await page.locator('#mapTools').boundingBox();
    assert(box.x >= 0 && box.x + box.width <= width + 1);
    assert(box.y + box.height <= Math.min(height, pane.y + pane.height));
    const row = options.first();
    assert(await row.evaluate(el => el.scrollWidth <= el.clientWidth));
    await page.screenshot({ path: path.join(evidence, `fish-search-${width}-zoom${zoom}.png`) });
    await input.press('ArrowUp');
    const last = await options.last().boundingBox();
    assert(last.y + last.height <= box.y + box.height + 1);
    check(`suggestions fit ${width}×${height} at ${zoom * 100}%`);
  }
  await page.evaluate(() => { document.documentElement.style.zoom = 1; });
  await page.setViewportSize({ width: 1400, height: 900 });
  await input.fill('Cloaking Shark');
  await page.locator('[data-page=journal]').click();
  await page.locator('[data-page=map]').click();
  assert.equal(await input.inputValue(), 'Cloaking Shark');
  await page.reload();
  await page.waitForFunction(() => !document.querySelector('#boot'));
  assert.equal(await input.inputValue(), '');
  assert.equal(await popup.isVisible(), false);
  check('tab round-trip keeps current search; reloaded application starts empty');
  // Synthetic in-memory sale; never sent to the service or a real journal.
  await page.evaluate(() => {
    state.sessions=[{id:'sale-visual',locationName:'Velia',tradingRank:'Guru',tradingLevel:100,
      items:[{itemId:820995,name:'Cloaking Shark',grade:'Prize',count:2,unitPrice:1000000}],
      sale:{destination:'Historical trader',bargainBonusPercent:12.5,distanceBonusPercent:120,
        marketPercent:100,finalAmount:1234567,soldAt:'2026-11-01T12:00:00Z'}}];
    openSalePlanner('sale-visual');
  });
  assert.equal(await page.locator('[data-sale-destination="0"]').inputValue(), 'Historical trader');
  assert.equal(await page.locator('#saleBargain').textContent(), '12.5%');
  assert.match(await page.locator('.sale-comparison').textContent(), /before freshness/);
  for (const [width,height,zoom] of [[1400,900,1],[1200,752,2]]) {
    await page.setViewportSize({width,height});
    await page.evaluate(z => {document.documentElement.style.zoom=z;},zoom);
    await page.locator('#saleModal').evaluate(el => {el.scrollTop=0;el.scrollLeft=0;});
    assert(await page.locator('#saleModal').evaluate(el => el.scrollWidth <= el.clientWidth+1),
      `Sale dialog must not have page-wide horizontal overflow at ${zoom*100}%`);
    await page.screenshot({path:path.join(evidence,`sale-assumptions-${width}-zoom${zoom}.png`)});
    await page.locator('#saleCancel').scrollIntoViewIfNeeded();
    const button=await page.locator('#saleCancel').boundingBox();
    const modal=await page.locator('#saleModal').boundingBox();
    report.saleLayouts ??= [];
    report.saleLayouts.push({width,height,zoom,button,modal});
    assert(button && button.x>=0 && button.y>=0 && button.x+button.width<=width+1 && button.y+button.height<=height+1,
      `Sale Cancel must be inside viewport at ${zoom*100}%: ${JSON.stringify(button)}`);
    check(`sale facts and fixed historical values remain reachable at ${zoom*100}%`);
  }
  await page.locator('#saleCancel').click();
  // Exercise current compiled API with an isolated synthetic mixed-price haul.
  const fixtureFish = await page.evaluate(() => state.fish.slice(0,2).map(f=>({itemId:f.itemId,name:f.name,grade:f.grade})));
  const api = async (route, method='GET', body) => {
    const response=await fetch(`${origin}${route}`,{method,
      headers:{'X-BSL-API-Token':token,'Content-Type':'application/json'},
      body:body===undefined?undefined:JSON.stringify(body)});
    assert(response.ok,`${method} ${route}: ${response.status}`);
    return response.json();
  };
  const haul=await api('/api/sessions','POST',{
    zoneRgb:'1,2,3',zoneName:'Synthetic value check',locationName:'Velia',method:'rod',style:'afk',
    durationMinutes:60,catches:fixtureFish.map((f,i)=>({...f,count:i?3:2,unitPrice:i?0:100}))});
  assert.equal(haul.baseValue,null);
  assert.equal(haul.knownValue,200);
  assert.equal(haul.unknownPriceFish,3);
  await api(`/api/sessions/${haul.id}/sale`,'PUT',{
    destination:'Historical trader',finalAmount:123456,bargainBonusPercent:0,
    soldAt:'2026-11-02T12:00:00Z'});
  const stats=await api('/api/stats');
  assert.equal(stats.totals.value,null);
  assert.equal(stats.totals.valuePerHour,null);
  assert.equal(stats.totals.fishPerHour,5);
  assert.equal(stats.spots[0].averageValuePer100,null);
  check('compiled API keeps incomplete values unknown and catch pace unchanged');
  await page.evaluate(async()=>{await loadSessions();renderJournal();});
  assert.match(await page.locator('#journalSummary').textContent(),/3 fish without prices/);
  assert.match(await page.locator('#journalList').textContent(),/3 fish without prices/);
  await page.evaluate(id=>openSalePlanner(id),haul.id);
  assert.equal(await page.locator('#saleTankValue').textContent(),'Unknown');
  assert.equal(await page.locator('[data-sale-rank="0"]').textContent(),'Price unknown');
  assert.equal(await page.locator('#saleFinalAmount').inputValue(),'123456');
  assert.equal(await page.locator('.sale-total-cell.is-best').count(),0);
  for(const [width,height,zoom] of [[1400,900,1],[1200,752,2]]) {
    await page.setViewportSize({width,height});
    await page.evaluate(z=>{document.documentElement.style.zoom=z;},zoom);
    await page.locator('#saleModal').evaluate(el=>{el.scrollTop=0;el.scrollLeft=0;});
    assert(await page.locator('#saleModal').evaluate(el=>el.scrollWidth<=el.clientWidth+1));
    await page.screenshot({path:path.join(evidence,`sale-unknown-${width}-zoom${zoom}.png`)});
    await page.locator('#saleCancel').scrollIntoViewIfNeeded();
    const button=await page.locator('#saleCancel').boundingBox();
    assert(button && button.x>=0 && button.y>=0 && button.x+button.width<=width+1 && button.y+button.height<=height+1);
  }
  await page.locator('#saleCancel').click();
  const recorded=await api(`/api/sessions/${haul.id}`);
  assert.equal(recorded.sale.finalAmount,123456);
  assert.equal(recorded.sale.bargainBonusPercent,0);
  assert.equal(recorded.baseValue,null);
  check('unknown-value sale UI never ranks partial totals; actual recorded sale preserved at normal/200%');
  for (const [width,height,zoom] of [[1400,900,1],[1200,752,2]]) {
    await page.setViewportSize({width,height});
    await page.evaluate(z => {document.documentElement.style.zoom=z;},zoom);
    for (const kind of ['profile','time']) {
      await page.evaluate(kind => kind==='profile' ? openProfileModal() : openTimePicker('start'),kind);
      const dialog=page.locator(kind==='profile' ? '.profile-modal' : '.time-picker');
      const cancel=page.locator(kind==='profile' ? '#profileCancel' : '#timePickerCancel');
      await cancel.scrollIntoViewIfNeeded();
      const box=await dialog.boundingBox();
      const button=await cancel.boundingBox();
      assert(box && box.x>=0 && box.y>=0 && box.x+box.width<=width+1 && box.y+box.height<=height+1,
        `${kind} dialog must fit at ${zoom*100}%: ${JSON.stringify(box)}`);
      assert(button && button.x>=0 && button.y>=0 && button.x+button.width<=width+1 && button.y+button.height<=height+1,
        `${kind} Cancel must be reachable at ${zoom*100}%: ${JSON.stringify(button)}`);
      await page.screenshot({path:path.join(evidence,`${kind}-dialog-${width}-zoom${zoom}.png`)});
      await cancel.click();
      check(`${kind} dialog fits and Cancel remains reachable at ${zoom*100}%`);
    }
  }
  assert.deepEqual(report.errors, []);
  report.passed = true;
} finally {
  await browser?.close();
  if (!stopped) { service.kill(); await once(service, 'close'); }
  report.serviceStopped = stopped;
  await fs.writeFile(path.join(evidence, 'browser-checks.json'), JSON.stringify(report, null, 2));
}
