// Real bundled Journal markup/styles with synthetic sessions. No service/profile access.
// Usage: node tool/test_journal_silver.mjs <playwright-module-url> <capture-directory>
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const {chromium}=await import(process.argv[2] || 'playwright');
const output=path.resolve(process.argv[3] || 'build/journal-silver');
await fs.mkdir(output,{recursive:true});
const payload=new URL('../assets/fish_companion/',import.meta.url);
const read=p=>fs.readFile(new URL(p,payload));
const html=(await read('static/index.html')).toString().replace(/<script[\s\S]*?<\/script>/g,'');
const css=(await read('static/app.css')).toString(),js=(await read('static/app.js')).toString();
assert.deepEqual(await read('static/silver.webp'),await fs.readFile(new URL('../../bdo_gathering_companion/assets/icons/item_artwork/1.webp',import.meta.url)));
const browser=await chromium.launch({headless:true,channel:'msedge'});
const checks=[];
try {
 const page=await browser.newPage({viewport:{width:1280,height:1100}});
 const errors=[];
 page.on('pageerror',e=>errors.push(String(e)));
 await page.route('**/*',async r=>{
  const p=new URL(r.request().url()).pathname;
  if(p==='/')return r.fulfill({contentType:'text/html',body:html});
  if(p==='/app.css')return r.fulfill({contentType:'text/css',body:css});
  if(p==='/silver.webp')return r.fulfill({contentType:'image/webp',body:await read('static/silver.webp')});
  const m=/^\/icon\/(\d+)\.webp$/.exec(p);
  if(m)try{return await r.fulfill({contentType:'image/webp',body:await read('data/cache/icons-4x/'+m[1].padStart(8,'0')+'.webp')});}catch{}
  return r.fulfill({status:404,body:''});
 });
 await page.goto('http://journal.test/');
 await page.addScriptTag({content:js});
 await page.evaluate(()=>{
  cacheElements();document.getElementById('boot').remove();els.app.classList.remove('is-hidden');
  document.querySelectorAll('.page').forEach(e=>e.classList.toggle('is-active',e.id==='page-journal'));
  document.getElementById('page-journal').style.display='block';
  const base={method:'rod',equipment:'Balenos Rod',mastery:1682,durationMinutes:180};
  state.sessions=[
   {...base,id:'sold',locationName:'Velia',caughtAt:'2026-11-07T08:00:00Z',
    items:[{itemId:8203,name:'Synthetic fish',count:24,unitPrice:130000,grade:'Rare'}],
    sale:{destination:'LotML',finalAmount:12645000,soldAt:'2026-11-07T12:00:00Z'}},
   {...base,id:'unsold',locationName:'Heidel',caughtAt:'2026-11-06T08:00:00Z',
    items:[{itemId:8203,name:'Synthetic fish',count:7,unitPrice:130000,grade:'Rare'}]},
   {...base,id:'unknown',locationName:'Unknown value example',caughtAt:'2026-11-05T08:00:00Z',
    items:[{itemId:8203,name:'Synthetic fish',count:1,unitPrice:null,grade:'Rare'}]},
   {...base,id:'legacy',locationName:'Legacy example',caughtAt:'2026-11-04T08:00:00Z',
    legacyAggregateOnly:true,totalFish:10,legacyReceivedSilver:123456,items:[]},
   {...base,id:'large',locationName:'Long value example',caughtAt:'2026-11-03T08:00:00Z',
    items:[],sale:{finalAmount:100000000000000,soldAt:'2026-11-03T12:00:00Z'}},
  ];renderJournal();
 });
 for(const [width,zoom] of [[1280,1],[1920,2],[720,1],[720,2]]) {
  await page.setViewportSize({width,height:1100});
  await page.evaluate(z=>document.getElementById('app').style.zoom=z,zoom);
  await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.querySelectorAll('#journalList img')].map(i=>i.decode()));});
  const result=await page.locator('#journalList').evaluate(list=>{
   const rect=e=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,right:r.right,bottom:r.bottom};};
   return [...list.querySelectorAll('.journal-row')].map(row=>({
    id:row.dataset.id,row:rect(row),
    values:[...row.querySelectorAll('.journal-value')].map(v=>({
     label:rect(v.querySelector('span')),amount:rect(v.querySelector('strong')),
     text:v.querySelector('strong').textContent,
     overflow:v.querySelector('strong').scrollWidth>v.querySelector('strong').clientWidth+1,
     icon:!!v.querySelector('img'),aria:v.querySelector('strong').getAttribute('aria-label'),
     hasHover:!!v.querySelector('[title]'),hasSuffix:!!v.querySelector('em'),
    })),
    actions:[...row.querySelectorAll('.journal-actions button')].map(b=>({className:b.className,rect:rect(b)})),
   }));
  });
  const sold=result.find(r=>r.id==='sold'),unsold=result.find(r=>r.id==='unsold');
  assert.equal(sold.values[0].text,'3,1M');assert.equal(sold.values[1].text,'12,6M');
  assert.equal(unsold.values[1].text,'—');assert(!unsold.values[1].icon);
  assert(result.find(r=>r.id==='unknown').values[0].text==='—');
  assert(!result.find(r=>r.id==='unknown').values[0].icon);
  assert(result.find(r=>r.id==='legacy').values[1].icon);
  for(const row of result) {
   for(let i=0;i<2;i++) {
    const v=row.values[i];assert(!v.hasHover&&!v.hasSuffix&&!v.overflow);
    assert(Math.abs(v.label.x-sold.values[i].label.x)<1,'Value columns align across rows');
    assert(Math.abs(v.amount.x-v.label.x)<1,'Value aligns with its label');
    assert(v.amount.right<=row.row.right+1,'Amount stays inside the card');
   }
   if(row.id!=='legacy') {
    const get=name=>row.actions.find(a=>a.className===name).rect;
    assert(Math.abs(get('journal-map-button').y-get('journal-edit-button').y)<1);
    assert(get('journal-sale-button').y>=get('journal-map-button').bottom,'Rejected one-row actions must not be applied');
   }
  }
  checks.push({width,zoom,rows:result});
  for (const id of ['sold','unknown','legacy','large']) {
   await page.locator('.journal-row[data-id="'+id+'"]').screenshot({path:path.join(output,'journal-'+width+'-'+zoom+'-'+id+'.png')});
  }
 }
 // Render actions remain wired to the same session IDs; no state mutation needed.
 await page.evaluate(()=>{
  globalThis.calls=[];
  showJournalSessionOnMap=id=>calls.push(['map',id]);
  openSalePlanner=id=>calls.push(['sale',id]);
  editSession=id=>calls.push(['edit',id]);
  deleteSession=id=>calls.push(['delete',id]);
 });
 for(const [cls,action] of [['journal-map-button','map'],['journal-sale-button','sale'],['journal-edit-button','edit'],['delete-session','delete']]) {
  await page.locator('[data-id="sold"] .'+cls).dispatchEvent('click');
 }
 assert.deepEqual(await page.evaluate(()=>calls),[['map','sold'],['sale','sold'],['edit','sold'],['delete','sold']]);
 assert.deepEqual(errors,[]);
 await fs.writeFile(path.join(output,'geometry.json'),JSON.stringify({syntheticOnly:true,checks,actionsUnchanged:true},null,2));
 console.log(JSON.stringify({passed:true,layouts:checks.length,rowsPerLayout:5,actions:4,offlineArtwork:true,personalDataAccess:false}));
} finally {await browser.close();}
