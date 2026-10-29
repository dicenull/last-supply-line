const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const base = process.env.WEB_URL || 'http://127.0.0.1:8791';
const out = path.resolve(process.env.WEB_AUDIT_DIR || 'build/map-shapes-web');
const results = [];
function check(ok,label){assert.ok(ok,label);results.push(label);console.log('PASS web map:',label);}
(async()=>{
  fs.mkdirSync(out,{recursive:true});
  const browser = await chromium.launch({headless:true,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
  try{
    await Promise.all([false,true].map(async touch=>{
      const name = touch?'mobile':'desktop', key = touch?'844':'1440';
      const context = await browser.newContext({viewport:touch?{width:844,height:390}:{width:1440,height:940},hasTouch:touch,isMobile:touch,deviceScaleFactor:touch?3:1});
      const page = await context.newPage(), errors = [];
      const touchSession=touch?await context.newCDPSession(page):null;
      page.on('pageerror',e=>errors.push(e.message));
      page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|ERROR:/.test(m.text()))errors.push(m.text());});
      const title = JSON.parse(fs.readFileSync('build/catalog-ui/title-geometry.json'))[key];
      const panes = JSON.parse(fs.readFileSync('build/loadout-ui/geometry.json'))[key];
      async function click(x,y){if(touch){await touchSession.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:0,x,y}]});await page.waitForTimeout(120);await touchSession.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}else await page.mouse.click(x,y,{delay:120});await page.waitForTimeout(350);}
      async function menu(x,y){const {width,height}=page.viewportSize(),s=Math.min(Math.max(Math.min(width/1440,height/940),0.9),(width-32)/480);await click((width-480*s)/2+(x-480)*s,(height-Math.min(748*s,height-32))/2+(y-96)*s);}
      async function load(){await page.goto(base,{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>!document.querySelector('#loading'),{},{timeout:120000});await page.waitForTimeout(1500);}
      let travelling=false;
      async function save(label){
        await click(...(travelling?panes.travel_footer:panes.footer).menu);await menu(700,308);await page.waitForTimeout(1800);
        const bytes = await page.evaluate(()=>new Promise((resolve,reject)=>{
          const request=indexedDB.open('/userfs');request.onerror=()=>reject(request.error);
          request.onsuccess=()=>{const db=request.result,tx=db.transaction('FILE_DATA','readonly'),cursor=tx.objectStore('FILE_DATA').openCursor();let bytes=null;
            cursor.onsuccess=()=>{const c=cursor.result;if(c){if(String(c.key).endsWith('/run_save.mfv'))bytes=Array.from(c.value.contents);c.continue();}};
            tx.oncomplete=()=>{db.close();resolve(bytes);};tx.onerror=()=>reject(tx.error);
          };
        }));
        check(bytes?.length>36,name+': '+label+' persists a save');
        const file=path.join(out,name+'-'+label+'.mfv');fs.writeFileSync(file,Buffer.from(bytes));
        const probe=spawnSync(process.env.GODOT||'/Applications/Godot.app/Contents/MacOS/Godot',['--headless','--path','.', '--script','tests/web_save_probe.gd','--',file],{encoding:'utf8'});
        assert.equal(probe.status,0,probe.stdout+probe.stderr);
        await menu(700,252);
        return JSON.parse(probe.stdout.match(/WEB SAVE: (.+)/)[1]);
      }
      await load();
      await click(...title.catalog);
      await page.screenshot({path:path.join(out,name+'-catalog.png')});
      await page.keyboard.press('Escape');await page.waitForTimeout(350);
      await click(...title.start);
      const initial=await save('initial');
      const stock=initial.gear_items.filter(i=>i.stock);
      check(stock.length===4&&stock.every(i=>i.position[0]===-2),name+': all four stock parts exist in inventory while equipped');
      check(initial.map_shape_version===1&&['fan','serpentine','switchback','ring','braid','long_route'].includes(initial.map_shape),name+': new browser run uses a versioned map shape');
      await click(...panes.footer.inventory);
      const {origin,scale}=panes.right;
      await click(origin[0]+100*scale,origin[1]+144*scale);
      await page.screenshot({path:path.join(out,name+'-selected.png')});
      if(!touch) await click(...panes.footer.warehouse);
      await click(...panes.footer.loadout);
      const target=JSON.parse(fs.readFileSync('build/equipment-audit/placement-geometry.json'))[key];
      if(!touch){
        await page.mouse.move(...target);await page.waitForTimeout(400);
        await page.screenshot({path:path.join(out,name+'-placement-preview.png')});
      }
      await click(...target);
      await page.screenshot({path:path.join(out,name+'-placed.png')});
      const placed=await save('placed');
      check(placed.gear_items.some(i=>i.uid===initial.gear_items[0].uid&&i.position[0]===0&&i.position[1]===0),name+': selecting an inventory item then clicking the deck places it without dragging');
      await click(...panes.footer.play);await page.waitForTimeout(2500);
      travelling=true;
      const travel=await save('travel');
      check(travel.started&&travel.phase==='travel'&&travel.map_geometry===initial.map_geometry,name+': combat uses the generated map');
      await load();await click(...title.continue);
      const restored=await save('restored');
      check(JSON.stringify(restored.gear_items)===JSON.stringify(travel.gear_items),name+': stock inventory survives reload without duplication');
      check(restored.map_shape===travel.map_shape&&restored.map_geometry===travel.map_geometry&&JSON.stringify(restored.player)===JSON.stringify(travel.player),name+': reload retains map geometry and tank position');
      await page.screenshot({path:path.join(out,name+'-restored.png')});
      check(errors.length===0,name+': no browser or engine errors: '+errors.join('\n'));
      await context.close();
    }));
    fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({base,checks:results.length,failures:0,results},null,2));
    console.log(`WEB MAP RESULT: ${results.length} checks, 0 failures`);
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
