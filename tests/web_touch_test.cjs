// Uses real browser touch events and the public save file; no game-state bridge.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const base = process.env.WEB_URL || 'http://127.0.0.1:8791';
const out = path.resolve(process.env.WEB_AUDIT_DIR || 'build/web-touch-audit');
const results = [], errors = [], logs = [];
function check(ok, label) { assert.ok(ok,label); results.push(label); console.log('PASS web touch:',label); }
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
  check(bytes?.length>36,label+': touchscreen action persists a save');
  const file=path.join(out,label+'.mfv');fs.writeFileSync(file,Buffer.from(bytes));
  const probe=spawnSync(process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot',['--headless','--path','.', '--script','tests/web_save_probe.gd','--',file],{encoding:'utf8'});
  assert.equal(probe.status,0,probe.stdout+probe.stderr);
  return JSON.parse(probe.stdout.match(/WEB SAVE: (.+)/)[1]);
}
(async()=>{
  fs.mkdirSync(out,{recursive:true});
  const browser=await chromium.launch({headless:true});
  try {
    const context=await browser.newContext({viewport:{width:844,height:390},deviceScaleFactor:1,isMobile:true,hasTouch:true});
    const page=await context.newPage();
    page.on('console',m=>{logs.push(m.type()+': '+m.text());if(m.type()==='error'||/SCRIPT ERROR|ERROR:/.test(m.text())) errors.push(m.text());});
    page.on('pageerror',e=>errors.push(e.message));
    async function load(){await page.goto(base,{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>!document.querySelector('#loading'),{},{timeout:120000});await page.waitForTimeout(1500);}
    function point(x,y){const {width,height}=page.viewportSize();const s=Math.min(width/1440,height/940);return {x:(width-1440*s)/2+x*s,y:(height-940*s)/2+y*s};}
    async function tap(x,y){const p=point(x,y);await page.touchscreen.tap(p.x,p.y);await page.waitForTimeout(200);}
    async function menuTap(x,y){
      const {width,height}=page.viewportSize();
      const scale=Math.min(Math.max(Math.min(width/1440,height/940),0.9),(width-32)/480);
      const left=(width-480*scale)/2, top=(height-Math.min(748*scale,height-32))/2;
      await page.touchscreen.tap(left+(x-480)*scale,top+(y-96)*scale);
      await page.waitForTimeout(250);
    }
    async function capture(name){await page.screenshot({path:path.join(out,name+'.png')});}
    async function save(label){await tap(1323.5,874.935);await menuTap(700,308);return readSave(page,label);}
    async function resumeMenu(){await menuTap(700,252);}
    await load();
    check(await page.evaluate(()=>navigator.maxTouchPoints>0),'browser exposes a real touch-capable viewport');
    await capture('title-landscape');
    await tap(200,431);
    await capture('construction');
    await tap(716,653); // shared processing category
    await capture('equipment-icons');
    await tap(164,759); // first equipment icon in the shared footer
    await tap(804.5,874.935); // inventory
    await capture('inventory');
    const inventoryScale=0.9, gameRight=page.viewportSize().width;
    await page.touchscreen.tap(gameRight-16-392*inventoryScale+131*inventoryScale,16+144*inventoryScale);
    await page.waitForTimeout(250); // original first row, tap-to-place
    await tap(634.146,166.461); // reserved grid (0,0)
    await tap(285.5,874.935); // rotate selected installed equipment
    const prepared=await save('prepared');
    check(!prepared.started && prepared.item_mode && JSON.stringify(prepared.gear_items[0].position)==='[0,0]','touch selection and placement install the gun');
    check(prepared.gear_items[0].direction===1,"touch rotation persists installed orientation");
    await resumeMenu();
    await tap(458.5,874.935); // storage mode
    await tap(634.146,166.461);
    const stowed=await save('stowed');
    check(JSON.stringify(stowed.gear_items[0].position)==='[-1,-1]','storage button replaces right-click');
    await resumeMenu();
    await tap(1150.5,874.935); // depart
    await page.waitForTimeout(18000);
    const stationary=await save('stationary');
    check(stationary.started && stationary.fuel>0 && stationary.manufactured>0,'touch departure runs real fuel and ammunition production');
    await resumeMenu();
    const cdp=await context.newCDPSession(page);
    const pad=point(170,550), pause=point(1150.5,874.935);
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:0,...pad}]});
    await page.waitForTimeout(2300);
    // Pause with a second finger while the first still holds the drive pad.
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:0,...pad},{id:1,...pause}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[{id:0,...pad}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await capture('driving');
    const moved=await save('moved');
    check(Math.hypot(...moved.player.map((v,i)=>v-stationary.player[i]))>0.2,'Godot virtual stick moves the actual tank');
    await resumeMenu();
    await page.waitForTimeout(1000);
    const paused=await save('paused');
    check(JSON.stringify(paused.player)===JSON.stringify(moved.player) && paused.ticks===moved.ticks,'second-finger pause leaves no stuck movement or simulation');
    await load();
    await tap(200,558);
    const restored=await save('restored');
    check(restored.seed===moved.seed && JSON.stringify(restored.player)===JSON.stringify(moved.player),'touch continue restores browser save after reload');
    await resumeMenu();
    await tap(1150.5,874.935); // resume, then rotate while running
    await page.setViewportSize({width:390,height:844});
    await page.waitForTimeout(800);
    check(await page.locator('#rotate').count()===0,'portrait menus remain available without an HTML rotation blocker');
    await capture('portrait');
    await page.setViewportSize({width:844,height:390});
    await page.waitForTimeout(800);
    await resumeMenu(); // portrait rotation opened the native pause menu
    const rotated=await save('rotated');
    await resumeMenu();
    await page.waitForTimeout(1200);
    const afterRotation=await save('after-rotation');
    check(rotated.ticks===afterRotation.ticks,'rotating to portrait pauses gameplay until explicitly resumed');
    check(errors.length===0,'no Godot or browser runtime errors: '+errors.join('\n'));
    fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({base,checks:results.length,failures:0,results,browser:browser.version()},null,2));
    console.log(`WEB TOUCH RESULT: ${results.length} checks, 0 failures`);
  } finally {fs.writeFileSync(path.join(out,'console.log'),logs.join('\n'));await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
