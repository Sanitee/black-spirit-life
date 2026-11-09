// Offline, synthetic Journal totals; optional baseline source verifies unchanged geometry.
// node tool/test_journal_summary_silver.mjs <playwright-module> <output-dir> [baseline-static-dir]
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const {chromium}=await import(process.argv[2] || 'playwright');
const output=path.resolve(process.argv[3] || 'build/journal-summary-silver');
await fs.mkdir(output,{recursive:true});
const payload=new URL('../assets/fish_companion/',import.meta.url);
const read=p=>fs.readFile(new URL(p,payload));
const html=(await read('static/index.html')).toString().replace(/<script[\s\S]*?<\/script>/g,'');
const css=(await read('static/app.css')).toString(),js=(await read('static/app.js')).toString();
const baseline=process.argv[4] ? await fs.readFile(path.join(process.argv[4],'app.js'),'utf8') : null;
const baselineCss=process.argv[4] ? await fs.readFile(path.join(process.argv[4],'app.css'),'utf8') : null;
const browser=await chromium.launch({headless:true,channel:'msedge'});
const errors=[],checks=[];
async function makePage(old=false){
 const page=await browser.newPage({viewport:{width:1280,height:1100}});
 page.on('pageerror',e=>errors.push(String(e)));
 await page.route('**/*',async r=>{
  const p=new URL(r.request().url()).pathname;
  if(p==='/')return r.fulfill({contentType:'text/html',body:html});
  if(p==='/app.css')return r.fulfill({contentType:'text/css',body:old?baselineCss:css});
  if(p==='/silver.webp')return r.fulfill({contentType:'image/webp',body:await read('static/silver.webp')});
  const m=/^\/icon\/(\d+)\.webp$/.exec(p);
  if(m)try{return await r.fulfill({contentType:'image/webp',body:await read('data/cache/icons-4x/'+m[1].padStart(8,'0')+'.webp')});}catch{}
  return r.fulfill({status:404,body:''});
 });
 await page.goto('http://journal.test/');await page.addScriptTag({content:old?baseline:js});
 await page.evaluate(()=>{
  cacheElements();document.getElementById('boot').remove();els.app.classList.remove('is-hidden');
  document.querySelectorAll('.page').forEach(e=>e.classList.toggle('is-active',e.id==='page-journal'));
  document.getElementById('page-journal').style.display='block';
 });return page;
}
async function render(page,scenario,width,zoom){
 await page.setViewportSize({width,height:1100});
 await page.evaluate(({scenario,zoom})=>{
   document.getElementById('app').style.zoom=zoom;
   const base={method:'rod',equipment:'Balenos Rod',mastery:1682,durationMinutes:180,caughtAt:'2026-11-09T08:00:00Z'};
   const sale={destination:'LotML',finalAmount:12645000,soldAt:'2026-11-09T12:00:00Z'};
   const sold={...base,id:'sold',locationName:'Velia',items:[{itemId:8203,name:'Synthetic fish',count:24,unitPrice:130000,grade:'Rare'}],sale};
   const other={...base,id:'unsold',locationName:'Heidel',items:[{itemId:8203,name:'Synthetic fish',count:7,unitPrice:130000,grade:'Rare'}]};
   state.sessions=scenario==='empty'?[]:scenario==='legacy'?[{...base,id:'legacy',locationName:'Imported example',legacyAggregateOnly:true,totalFish:10,legacyReceivedSilver:123456,items:[]}]:scenario==='unknown'?[{...other,items:[{...other.items[0],unitPrice:null}]}]:[sold,other];
   renderJournal();
 },{scenario,zoom});
 await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.querySelectorAll('#journalSummary img')].map(i=>i.decode()));});
 return page.locator('#journalSummary').evaluate(el=>{
  const rect=e=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};};
  return {rect:rect(el),text:el.innerText,overflow:el.scrollWidth>el.clientWidth+1,
   cells:[...el.children].map(c=>({rect:rect(c),heading:rect(c.querySelector('span')),amount:rect(c.querySelector('strong')),text:c.querySelector('strong').innerText,aria:c.querySelector('strong').getAttribute('aria-label'),icon:!!c.querySelector('strong img')})),
   images:[...el.querySelectorAll('img')].map(i=>({complete:i.complete,width:i.getBoundingClientRect().width,height:i.getBoundingClientRect().height})),
   hover:!!el.querySelector('[title]')};
 });
}
try{
 const page=await makePage(),old=baseline?await makePage(true):null;
 for(const [width,zoom] of [[1280,1],[1920,2],[720,1],[720,2]])for(const scenario of ['known','empty','unknown','legacy']){
  const after=await render(page,scenario,width,zoom);
  assert(!after.hover);assert(after.images.every(i=>i.complete&&i.width>0&&i.height>0));
  if(scenario==='known'){
   assert.equal(after.cells[2].text,'4,0M');assert.equal(after.cells[3].text,'12,6M');
   assert(after.cells[2].icon&&after.cells[3].icon);assert.match(after.cells[2].aria,/4\.030\.000 silver/);
  }else if(scenario==='empty'){
   assert.equal(after.cells[2].text,'0');assert(after.cells[2].icon);assert.equal(after.cells[3].text,'—');assert(!after.cells[3].icon);
  }else if(scenario==='unknown'){
   assert.equal(after.cells[2].text,'—');assert(!after.cells[2].icon);assert.match(after.text,/7 fish without prices/);
  }else{
   assert.equal(after.cells[2].text,'—');assert.equal(after.images.length,1);assert.match(after.text,/Legacy received/);assert.match(after.text,/Excludes 1 aggregate-only import/);
  }
  if(old){
   const before=await render(old,scenario,width,zoom);
   await fs.writeFile(path.join(output,'last-comparison.json'),JSON.stringify({scenario,width,zoom,before,after},null,2));
   assert.equal(after.overflow,before.overflow,'No new summary overflow');
   assert.equal(after.text.replace(/\s/g,''),before.text.replace(/silver/gi,'').replace(/\s/g,''));
   if(scenario!=='legacy')for(let i=0;i<4;i++)for(const part of ['rect','heading','amount'])for(const axis of ['x','y','width','height']){
    const beforeValue=before.cells[i][part][axis]-(axis==='x'||axis==='y'?before.rect[axis]:0);
    const afterValue=after.cells[i][part][axis]-(axis==='x'||axis==='y'?after.rect[axis]:0);
    assert(Math.abs(beforeValue-afterValue)<1,`Original geometry changed: ${scenario} ${width}/${zoom} cell${i} ${part}.${axis}`);
   }
  }
  assert(!after.overflow,'Summary stays within available width');
  checks.push({width,zoom,scenario,...after});
  await page.locator('#journalSummary').screenshot({path:path.join(output,`summary-${scenario}-${width}-${zoom}.png`)});
 }
 assert.deepEqual(errors,[]);
 await fs.writeFile(path.join(output,'geometry.json'),JSON.stringify({syntheticOnly:true,checks,baselineCompared:!!baseline},null,2));
 console.log(JSON.stringify({passed:true,scenarios:checks.length,originalAlignmentPreserved:!!baseline,personalDataAccess:false}));
}finally{await browser.close();}
