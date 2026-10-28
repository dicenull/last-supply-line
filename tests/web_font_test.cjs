const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const base = process.env.WEB_URL || 'http://127.0.0.1:8791';
const out = path.resolve(process.env.WEB_AUDIT_DIR || 'build/web-font-audit');
const results = [];
function check(ok,label) {assert.ok(ok,label); results.push(label); console.log('PASS web font:',label);}
(async()=>{
  fs.mkdirSync(out,{recursive:true});
  const browser = await chromium.launch({headless:false,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
  let desktopPage;
  try {
    await Promise.all([{touch:false,dpr:1},{touch:true,dpr:1},{touch:true,dpr:3}].map(async ({touch,dpr})=>{
      const name = touch ? 'touch-'+dpr+'x' : 'desktop';
      const context = await browser.newContext({viewport:touch?{width:844,height:390}:{width:1440,height:940},hasTouch:touch,isMobile:touch,deviceScaleFactor:dpr});
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror',e=>errors.push(e.message));
      page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|ERROR:/.test(m.text())) errors.push(m.text());});
      const fontResponse = page.waitForResponse(r=>r.url()===base+'/NotoSansJP.woff2');
      await page.goto(base,{waitUntil:'domcontentloaded'});
      const response = await fontResponse;
      check(response.ok() && (await response.body()).subarray(0,4).toString()==='wOF2',name+': same-origin Japanese WOFF2 is served');
      await page.evaluate(()=>document.fonts.ready);
      const fonts = await page.evaluate(()=>({
        loaded:Array.from(document.fonts).some(f=>f.family==='Noto Sans JP' && f.status==='loaded'),
        button:getComputedStyle(document.querySelector('#fullscreen')).fontFamily,
        japanese:document.fonts.check('16px "Noto Sans JP"','全画面を終了 日本語')
      }));
      check(fonts.loaded && fonts.japanese && fonts.button.includes('Noto Sans JP'),name+': page and fullscreen button use the downloaded Japanese font');
      await page.waitForFunction(()=>!document.querySelector('#loading'),{},{timeout:120000});
      await page.waitForTimeout(1200);
      await page.screenshot({path:path.join(out,name+'-title.png')});
      async function click(x,y){if(touch)await page.touchscreen.tap(x,y);else await page.mouse.click(x,y);await page.waitForTimeout(350);}
      async function menu(x,y){const {width,height}=page.viewportSize(),s=Math.min(Math.max(Math.min(width/1440,height/940),0.9),(width-32)/480);await click((width-480*s)/2+(x-480)*s,(height-Math.min(748*s,height-32))/2+(y-96)*s);}
      async function checkResolution(){
        const pixels=await page.evaluate(()=>{const c=document.querySelector('canvas'),r=c.getBoundingClientRect();return {width:c.width,height:c.height,cssWidth:r.width,cssHeight:r.height,dpr:devicePixelRatio,innerWidth,innerHeight,visualScale:visualViewport.scale};});
        console.log(name+': screen metrics',JSON.stringify(pixels));
        check(Math.abs(pixels.cssWidth-page.viewportSize().width)<=1 && Math.abs(pixels.cssHeight-page.viewportSize().height)<=1,name+': canvas fits the current browser viewport after rotation');
        check(Math.abs(pixels.width-pixels.cssWidth*dpr)<=2 && Math.abs(pixels.height-pixels.cssHeight*dpr)<=2,name+': canvas renders at actual device pixel density');
      }
      await checkResolution();
      const title=JSON.parse(fs.readFileSync('build/catalog-ui/title-geometry.json'))[touch?'844':'1440'];
      const panes=JSON.parse(fs.readFileSync('build/loadout-ui/geometry.json'))[touch?'844':'1440'];
      await click(...title.start);
      await click(...panes.footer.menu);
      await page.screenshot({path:path.join(out,name+'-pause.png')});
      await menu(700,476); // Settings, using the same CSS coordinates at 1x and 3x.
      await menu(700,296); // Mute proves the scaled menu's actual input coordinates.
      async function waitMuted(expected){await page.waitForFunction(async expected=>{
        if(!(await indexedDB.databases()).some(d=>d.name==='/userfs'))return false;
        return new Promise(resolve=>{const request=indexedDB.open('/userfs');request.onsuccess=()=>{const db=request.result,tx=db.transaction('FILE_DATA','readonly'),cursor=tx.objectStore('FILE_DATA').openCursor();let muted=false;
          cursor.onsuccess=()=>{const c=cursor.result;if(c){if(String(c.key).endsWith('/audio_settings.json'))muted=(JSON.parse(new TextDecoder().decode(c.value.contents)).volume===0)===expected;c.continue();}};
          tx.oncomplete=()=>{db.close();resolve(muted);};};});
      },expected,{timeout:15000});}
      await waitMuted(true);
      check(true,name+': menu input and persisted mute match CSS coordinates at this pixel density');
      await page.screenshot({path:path.join(out,name+'-settings.png')});
      if(touch){
        await page.setViewportSize({width:390,height:844});
        await page.waitForTimeout(700);
        await checkResolution();
        await menu(700,296);
        await waitMuted(false);
        check(true,name+': menu stays readable and tappable after landscape-to-portrait rotation');
        await page.screenshot({path:path.join(out,name+'-portrait-settings.png')});
      }else{
        await menu(864,160);
        await menu(700,252);
        await page.screenshot({path:path.join(out,name+'-game.png')});
      }
      check(errors.length===0,name+': title and game start without missing fonts or runtime errors: '+errors.join('\n'));
      if(touch) await context.close();
      else desktopPage = page;
    }));
    // Capture the native popup with the desktop window active after parallel checks.
    await desktopPage.bringToFront();
    await desktopPage.mouse.move(700,800);
    await desktopPage.mouse.move(720,888,{steps:10});
    await desktopPage.waitForTimeout(1800);
    await desktopPage.screenshot({path:path.join(out,'desktop-japanese-tooltip.png')});
    fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({base,checks:results.length,failures:0,results},null,2));
    console.log(`WEB FONT RESULT: ${results.length} checks, 0 failures`);
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
