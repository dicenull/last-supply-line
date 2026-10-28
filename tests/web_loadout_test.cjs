// Uses real browser touch events and the public save file; no game-state bridge.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const base = process.env.WEB_URL || 'http://127.0.0.1:8791';
const out = path.resolve(process.env.WEB_AUDIT_DIR || 'build/web-loadout-audit');
const results = [], errors = [], logs = [];
function check(ok, label) { assert.ok(ok,label); results.push(label); console.log('PASS web loadout:',label); }
async function readSave(page,label) {
  await page.waitForTimeout(1800);
  const bytes = await page.evaluate(async () => {
    const info = (await indexedDB.databases()).find(d=>d.name==='/userfs');
    if (!info) return null;
    return new Promise((resolve,reject)=>{
      const open = indexedDB.open(info.name);
      open.onerror=()=>reject(open.error);
      open.onsuccess=()=>{
        const db=open.result, tx=db.transaction('FILE_DATA','readonly');
        const request=tx.objectStore('FILE_DATA').openCursor(); let found=null;
        request.onsuccess=()=>{const c=request.result;if(c){if(String(c.key).endsWith('/run_save.mfv')) found=Array.from(c.value.contents);c.continue();}};
        tx.oncomplete=()=>{db.close();resolve(found);};
      };
    });
  });
  check(bytes?.length>36,label+': operation persists a save');
  const file=path.join(out,label+'.mfv');fs.writeFileSync(file,Buffer.from(bytes));
  const probe=spawnSync(process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot',['--headless','--path','.', '--script','tests/web_save_probe.gd','--',file],{encoding:'utf8'});
  assert.equal(probe.status,0,probe.stdout+probe.stderr);
  return JSON.parse(probe.stdout.match(/WEB SAVE: (.+)/)[1]);
}

(async()=>{
  fs.mkdirSync(out,{recursive:true});
  const touch=process.env.TOUCH==='1';
  const dpr=Number(process.env.DPR||1);
  const titlePoints=JSON.parse(fs.readFileSync('build/catalog-ui/title-geometry.json'))[touch?'844':'1440'];
  const panePoints=JSON.parse(fs.readFileSync('build/loadout-ui/geometry.json'))[touch?'844':'1440'];
  const browser=await chromium.launch({headless:false});
  try {
    const context=await browser.newContext({viewport:touch?{width:844,height:390}:{width:1440,height:940},isMobile:touch,hasTouch:touch,deviceScaleFactor:dpr});
    const page=await context.newPage();
    const touchSession=touch?await context.newCDPSession(page):null;
    page.on('console',m=>{logs.push(m.type()+': '+m.text());if(m.type()==='error'||/SCRIPT ERROR|ERROR:/.test(m.text())) errors.push(m.text());});
    page.on('pageerror',e=>errors.push(e.message));
    async function load(){await page.goto(base,{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>!document.querySelector('#loading'),{},{timeout:120000});await page.waitForTimeout(1500);}
    async function click(x,y){if(touch){await touchSession.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:0,x,y}]});await page.waitForTimeout(120);await touchSession.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}else await page.mouse.click(x,y,{delay:120});await page.waitForTimeout(250);}
    async function game(x,y){const {width,height}=page.viewportSize(),s=Math.min(width/1440,height/940);await click((width-1440*s)/2+x*s,(height-940*s)/2+y*s);}
    async function menu(x,y){const {width,height}=page.viewportSize(),s=Math.min(Math.max(Math.min(width/1440,height/940),0.9),(width-32)/480);await click((width-480*s)/2+(x-480)*s,(height-Math.min(748*s,height-32))/2+(y-96)*s);}
    async function footer(id){await click(...panePoints.footer[id]);}
    async function inventory(x,y){const {origin,scale}=panePoints.right;await click(origin[0]+x*scale,origin[1]+y*scale);if(x===358 && y===28 && !panePoints.narrow) await click(...panePoints.left_close);}
    async function save(label){await footer('menu');await menu(700,308);const result=await readSave(page,label);await menu(700,252);return result;}
    await load();
    await click(...titlePoints.catalog);
    await page.screenshot({path:path.join(out,'title-catalog.png')});
    await click(touch?433:480,touch?145:180);
    await page.screenshot({path:path.join(out,'catalog-selected.png')});
    await click(touch?178:196,touch?32:34);
    await click(...titlePoints.start);await save('initial');
    // Replace only this isolated browser context's save while the game is unloaded.
    await page.route('**/loadout-fixture',route=>route.fulfill({contentType:'text/html',body:'<link rel="icon" href="data:,">'}));
    async function installFixture(file) {
    await page.goto(base+'/loadout-fixture');
    const fixture=Array.from(fs.readFileSync(file));
    await page.evaluate(bytes=>new Promise((resolve,reject)=>{
      const open=indexedDB.open('/userfs');open.onerror=()=>reject(open.error);
      open.onsuccess=()=>{const db=open.result,tx=db.transaction('FILE_DATA','readwrite'),store=tx.objectStore('FILE_DATA');let replaced=false;
        const request=store.openCursor();request.onsuccess=()=>{const c=request.result;if(c){if(String(c.key).endsWith('/run_save.mfv')){c.update({...c.value,contents:new Uint8Array(bytes),timestamp:new Date()});replaced=true;}c.continue();}};
        tx.oncomplete=()=>{db.close();replaced?resolve():reject(new Error('save not found'));};tx.onerror=()=>reject(tx.error);
      };
    }),fixture);
    }
    await installFixture('build/loadout-ui/web-fixture.mfv');
    await load();await click(...titlePoints.continue);
    await footer('inventory');
    for(let tab=1;tab<=4;tab++){
      await inventory(50+tab*72,76);
      if(panePoints.right.page_size===1) await inventory(336,panePoints.right.height-24);
      const replacementY=panePoints.right.page_size===1?144:226;
      await inventory(131,replacementY); // The first row is the equipped stock part.
      await inventory(281,replacementY);
    }
    await page.screenshot({path:path.join(out,'equipped-inventory.png')});
    await inventory(358,28);
    await page.screenshot({path:path.join(out,'equipped-tank.png')});
    const equipped=await save('equipped');
    for(const kind of ['vehicle_gear_torque','vehicle_engine_power','vehicle_tracks_wide','vehicle_cannon_howitzer'])
      check(equipped.gear_items.some(i=>i.kind===kind&&i.position[0]===-2),'swap equips '+kind);
    await footer('inventory');await inventory(194,76);
    if(panePoints.right.page_size===1) {await inventory(336,panePoints.right.height-24);await inventory(336,panePoints.right.height-24);}
    await inventory(281,panePoints.right.page_size===1?144:308);await inventory(358,28);
    const swapped=await save('swapped');
    check(swapped.gear_items.some(i=>i.kind==='vehicle_engine_power'&&i.position[0]===-1),'old engine returns to storage');
    check(swapped.gear_items.some(i=>i.kind==='vehicle_engine_efficient'&&i.position[0]===-2),'replacement engine equips');
    await load();await click(...titlePoints.continue);
    const restored=await save('restored');
    check(JSON.stringify(restored.gear_items)===JSON.stringify(swapped.gear_items),'all equipment survives browser reload');
    if(!touch){
      await page.keyboard.down('w');await page.waitForTimeout(350);await page.keyboard.up('w');
      await page.keyboard.down('d');await page.waitForTimeout(250);await page.keyboard.up('d');
      const panned=await save('camera-pan');
      check(Math.hypot(...panned.camera_offset)>0.1,'WASD pans construction camera');
      check(JSON.stringify(panned.player)===JSON.stringify(restored.player),'construction panning leaves the tank stationary');
    }
    await footer('inventory');
    for(let tab=1;tab<=4;tab++) {
      await inventory(50+tab*72,76);
      const row=tab===2?2:1;
      for(let i=0;i<Math.floor(row/panePoints.right.page_size);i++) await inventory(336,panePoints.right.height-24);
      await inventory(346,144+(row%panePoints.right.page_size)*82);
    }
    await page.screenshot({path:path.join(out,'empty-loadout.png')});
    await inventory(358,28);
    await page.screenshot({path:path.join(out,'empty-tank.png')});
    const empty=await save('empty');
    check(empty.empty_slots.length===4,'warehouse combined stow buttons empty all four slots');
    check(empty.gear_items.every(i=>i.position[0]!==-2),'removed parts remain in storage');
    await load();await click(...titlePoints.continue);
    const emptyRestored=await save('empty-restored');
    check(JSON.stringify(emptyRestored.empty_slots)===JSON.stringify(empty.empty_slots),'empty appearance state survives browser reload');
    await installFixture('build/result-ui/web-fixture.mfv');
    await load();await click(...titlePoints.continue);
    const resultPoints=JSON.parse(fs.readFileSync('build/result-ui/geometry.json'))[touch?'844':'1440'];
    await click(...resultPoints[1]);
    await page.screenshot({path:path.join(out,'clear-equipment.png')});
    await click(...resultPoints[0]);
    await page.screenshot({path:path.join(out,'game-clear.png')});
    await click(...resultPoints[5]);
    const victory=await readSave(page,'victory');
    check(victory.phase==='won' && victory.results.kills>0 && victory.results.settled.includes(5),'clear screen returns to title with durable results');
    await click(...titlePoints.continue);
    await click(...resultPoints[4]);
    const retry=await save('retry');
    check(retry.phase==='prepare' && retry.results.kills===0,'clear screen retry resets campaign results');
    check(errors.length===0,'no runtime errors: '+errors.join('\n'));
    fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({base,touch,dpr,checks:results.length,failures:0,results},null,2));
    console.log(`WEB LOADOUT RESULT: ${results.length} checks, 0 failures`);
  } finally {fs.writeFileSync(path.join(out,'console.log'),logs.join('\n'));await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
