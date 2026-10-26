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
    await Promise.all([false,true].map(async touch=>{
      const name = touch ? 'touch' : 'desktop';
      const context = await browser.newContext({viewport:touch?{width:844,height:390}:{width:1440,height:940},hasTouch:touch,isMobile:touch});
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
      const s=touch?390/940:1, left=touch?(844-1440*s)/2:0;
      if(touch) await page.touchscreen.tap(left+200*s,431*s);
      else await page.mouse.click(200,431);
      await page.waitForTimeout(1200);
      await page.screenshot({path:path.join(out,name+'-game.png')});
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
