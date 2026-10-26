const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const base=process.env.WEB_URL||'http://127.0.0.1:8791';
const out=path.resolve(process.env.WEB_AUDIT_DIR||'build/web-responsive-audit');
const results=[];
(async()=>{
  fs.mkdirSync(out,{recursive:true});
  const browser=await chromium.launch({headless:false,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
  try {
    await Promise.all([false,true].map(async touch=>{
      const name=touch?'touch':'mouse',errors=[];
      const context=await browser.newContext({viewport:{width:390,height:844},isMobile:touch,hasTouch:touch,deviceScaleFactor:1});
      const page=await context.newPage();
      page.on('pageerror',e=>errors.push(e.message));
      page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|ERROR:/.test(m.text()))errors.push(m.text());});
      async function click(x,y){if(touch)await page.touchscreen.tap(x,y);else await page.mouse.click(x,y);await page.waitForTimeout(350);}
      await page.goto(base,{waitUntil:'domcontentloaded'});
      await page.waitForFunction(()=>!document.querySelector('#loading'),{},{timeout:120000});
      await page.waitForTimeout(1400);
      assert.equal(await page.locator('#rotate').count(),0,'portrait UI is not blocked');
      await page.screenshot({path:path.join(out,name+'-portrait-title.png')});
      await click(120,581); // Common portrait title: settings, third left-aligned row.
      await page.screenshot({path:path.join(out,name+'-portrait-settings.png')});
      const factor=(390-32)/480,top=(844-748*factor)/2;
      await click(16+(700-480)*factor,top+(296-96)*factor); // Original mute row.
      await page.waitForFunction(async()=>{
        const names=await indexedDB.databases();if(!names.some(d=>d.name==='/userfs'))return false;
        return new Promise(resolve=>{
          const request=indexedDB.open('/userfs');
          request.onsuccess=()=>{
            const db=request.result,tx=db.transaction('FILE_DATA','readonly'),cursor=tx.objectStore('FILE_DATA').openCursor();let muted=false;
            cursor.onsuccess=()=>{const c=cursor.result;if(c){if(String(c.key).endsWith('/audio_settings.json'))muted=JSON.parse(new TextDecoder().decode(c.value.contents)).volume===0;c.continue();}};
            tx.oncomplete=()=>{db.close();resolve(muted);};
          };
        });
      },{},{timeout:15000});
      results.push(name+': portrait settings work with the common menu');
      await click(16+(864-480)*factor,top+(160-96)*factor); // Back.
      await page.setViewportSize({width:844,height:390});
      await page.waitForTimeout(700);
      await page.screenshot({path:path.join(out,name+'-landscape-title.png')});
      await click(120,273); // Same title menu after resizing, settings.
      await page.screenshot({path:path.join(out,name+'-landscape-settings.png')});
      assert.equal(errors.length,0,errors.join('\n'));
      results.push(name+': resize has no browser or Godot errors');
      await context.close();
    }));
    fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({base,checks:results.length,failures:0,results},null,2));
    console.log('WEB RESPONSIVE RESULT:',results.length,'checks, 0 failures');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
