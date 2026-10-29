// Run after `npm run dev:web`, using an isolated browser context (no player saves).
// WEB_URL=http://127.0.0.1:8791 GODOT=/path/to/Godot node tests/web_smoke_test.cjs
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const assert = require('node:assert/strict');
const out = path.resolve(process.env.WEB_AUDIT_DIR || 'build/web-audit');
const base = process.env.WEB_URL || 'http://127.0.0.1:8791';
const godot = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const results = [], logs = [], errors = [];
function check(ok, name) { assert.ok(ok, name); results.push(name); console.log('PASS web:', name); }
async function savedBytes(page) {
  return page.evaluate(async () => {
    const info = (await indexedDB.databases()).find(d => d.name === '/userfs');
    if (!info) return null;
    return new Promise((resolve, reject) => {
      const open = indexedDB.open(info.name);
      open.onerror = () => reject(open.error);
      open.onsuccess = () => {
        const db = open.result;
        const tx = db.transaction('FILE_DATA', 'readonly');
        const cursor = tx.objectStore('FILE_DATA').openCursor();
        let found = null;
        cursor.onsuccess = () => {
          const c = cursor.result;
          if (c) {
            if (String(c.key).endsWith('/run_save.mfv')) found = Array.from(c.value.contents);
            c.continue();
          }
        };
        tx.oncomplete = () => { db.close(); resolve(found); };
        tx.onerror = () => { db.close(); reject(tx.error); };
      };
    });
  });
}
async function readSave(page, label, previousBytes = null) {
  let bytes;
  for (let i = 0; i < 50; i++) {
    bytes = await savedBytes(page);
    if (bytes?.length && (!previousBytes || !Buffer.from(bytes).equals(Buffer.from(previousBytes)))) break;
    await page.waitForTimeout(200);
  }
  check(bytes?.length > 36, label + ': persisted IndexedDB save');
  const file = path.join(out, label + '.mfv');
  fs.writeFileSync(file, Buffer.from(bytes));
  const run = spawnSync(godot, ['--headless', '--path', '.', '--script', 'tests/web_save_probe.gd', '--', file], {encoding:'utf8'});
  assert.equal(run.status, 0, run.stdout + run.stderr);
  const match = run.stdout.match(/WEB SAVE: (.+)/);
  assert.ok(match, run.stdout + run.stderr);
  return { bytes, state: JSON.parse(match[1]) };
}
async function openGame(page) {
  await page.goto(base, {waitUntil:'domcontentloaded', timeout:60000});
  await page.waitForFunction(() => !document.querySelector('#loading'), {}, {timeout:120000});
  await page.waitForTimeout(1800);
}
async function press(page, key) {
  await page.keyboard.press(key);
  // The engine consumes browser events on its render loop. Give each menu
  // transition a frame before sending a different action, including in parallel runs.
  await page.waitForTimeout(200);
}
(async () => {
  fs.mkdirSync(out, {recursive:true});
  const browser = await chromium.launch({headless:true,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
  try {
    const context = await browser.newContext({viewport:{width:1440,height:940}});
    // Observe the actual output signal without changing or unmuting the game.
    await context.addInitScript(() => {
      window.__audioProbes = [];
      const Original = window.AudioContext;
      if (Original) window.AudioContext = new Proxy(Original, {
        construct(Target, args) {
          const ctx = new Target(...args), analyser = ctx.createAnalyser();
          analyser.fftSize = 256;
          const originalConnect = AudioNode.prototype.connect;
          const priorConnect = ctx.destination;
          const silent = ctx.createGain();
          silent.gain.value = 0;
          originalConnect.call(analyser, silent);
          originalConnect.call(silent, ctx.destination);
          window.__audioProbes.push({ctx, analyser});
          AudioNode.prototype.connect = function(destination, ...rest) {
            if (destination === priorConnect && this !== analyser) originalConnect.call(this, analyser);
            return originalConnect.call(this, destination, ...rest);
          };
          return ctx;
        }
      });
    });
    const page = await context.newPage();
    page.on('console', m => {
      logs.push(m.type() + ': ' + m.text());
      if (m.type() === 'error' || /SCRIPT ERROR|ERROR:/.test(m.text())) errors.push(m.text());
    });
    page.on('pageerror', e => errors.push(e.message));
    await openGame(page);
    check(/M\.F\.V\. 03|AMMO LINE LAB/.test(await page.title()), 'browser starts release build');
    await page.screenshot({path:path.join(out,'title.png')});
    const wasm = await page.request.get(base + '/index.wasm');
    check(wasm.headers()['content-type'] === 'application/wasm', 'WASM MIME type');
    check((await wasm.body()).subarray(0,4).equals(Buffer.from([0,97,115,109])), 'WASM decodes once');
    check((await page.request.get(base + '/missing-asset.wasm')).status() === 404, 'missing asset returns 404');
    await page.mouse.click(200,431); // 専用タイトルから準備へ
    await page.waitForTimeout(400);
    await page.screenshot({path:path.join(out,'construction.png')});
    await press(page, 'i');
    await page.waitForTimeout(250);
    await page.mouse.move(1147,244);
    await page.mouse.down();
    await page.mouse.move(1117,244,{steps:3});
    await page.mouse.move(591,207,{steps:12}); // Initial camera: grid cell (0,0).
    await page.waitForTimeout(200);
    await page.screenshot({path:path.join(out,'equipment-drag.png')});
    await page.mouse.up();
    await press(page, 'i');
    await page.waitForTimeout(250);
    await page.mouse.click(1362,408); // Dismantle the stowed uncommon economizer.
    await page.screenshot({path:path.join(out,'equipment-inventory.png')});
    await press(page, 'i');
    await press(page, 'Escape');
    await page.mouse.click(650,308); // ランを保存
    await page.waitForTimeout(1500);
    const prepared = await readSave(page, 'prepared');
    check(!prepared.state.started && prepared.state.phase === 'prepare', 'preparation saves before departure');
    check(prepared.state.layout_version === 2 && prepared.state.item_mode, 'new browser run uses central stock hull and equipment economy');
    check(prepared.state.gear_items.filter(i=>!i.stock).length === 2 && prepared.state.gear_items[0].kind === 'left_gun' &&
      JSON.stringify(prepared.state.gear_items[0].position) === '[0,0]', 'browser drag installs equipment on its reserved footprint');
    check(prepared.state.reserves.scrap === 57 && prepared.state.reserves.coal === 35,
      'browser dismantling turns stowed equipment into construction materials');
    await press(page, 'Escape');
    await press(page, 'Space');
    await page.waitForTimeout(16000);
    await press(page, 'Escape');
    await page.mouse.click(650,308);
    await page.waitForTimeout(1500);
    const stationary = await readSave(page, 'stationary',prepared.bytes);
    check(stationary.state.started && stationary.state.phase === 'travel', 'Space starts combat');
    check(stationary.state.manufactured > 0 && stationary.state.fuel > 0, 'real production supplies combat');
    await press(page, 'Escape');
    await page.keyboard.down('w');
    await page.waitForTimeout(3500);
    const audioPeak = await page.evaluate(async () => {
      let peak = 0;
      for (let i=0;i<20;i++) {
        for (const {analyser} of window.__audioProbes) {
          const data = new Float32Array(analyser.fftSize);
          analyser.getFloatTimeDomainData(data);
          for (const v of data) peak = Math.max(peak, Math.abs(v));
        }
        await new Promise(r=>setTimeout(r,50));
      }
      return peak;
    });
    check(audioPeak > 0, 'audio produces a nonzero signal while driving');
    await page.keyboard.up('w');
    await page.screenshot({path:path.join(out,'combat.png')});
    await press(page, 'Escape');
    await page.mouse.click(650,308);
    await page.waitForTimeout(1500);
    const moved = await readSave(page, 'moved');
    check(Math.hypot(...moved.state.player.map((v,i)=>v-stationary.state.player[i])) > 0.2, 'W moves the tank');
    await openGame(page); // True browser reload, reconstructing IndexedDB user://.
    check(Buffer.from(await savedBytes(page)).equals(Buffer.from(moved.bytes)), 'browser reload retains exact save');
    await page.mouse.click(200,501); // 続きから
    await page.waitForTimeout(1800);
    await page.screenshot({path:path.join(out,'restored.png')});
    await press(page, 'Escape');
    await page.mouse.click(650,308);
    await page.waitForTimeout(1500);
    const restored = await readSave(page, 'restored');
    check(restored.state.seed === moved.state.seed && restored.state.ticks === moved.state.ticks &&
      JSON.stringify(restored.state.player) === JSON.stringify(moved.state.player), 'continue restores position and production, paused');
    check(JSON.stringify(restored.state.gear_items) === JSON.stringify(moved.state.gear_items),
      'browser reload retains equipment identities, rarities and installed positions');
    await page.mouse.click(650,700); // 保存してタイトルへ
    await page.waitForTimeout(2500);
    await page.mouse.click(200,501); // 続きから still works after scene reload.
    await page.waitForTimeout(1500);
    await press(page, 'Escape');
    await page.mouse.click(650,308);
    await page.waitForTimeout(1500);
    const returned = await readSave(page, 'returned');
    check(returned.state.seed === moved.state.seed && returned.state.started, 'save-to-title allows continuing without engine shutdown');
    await page.setViewportSize({width:960,height:628});
    await page.waitForTimeout(1200);
    await page.screenshot({path:path.join(out,'small-menu.png')});
    const canvas = await page.locator('canvas').boundingBox();
    check(canvas.width <= 960 && canvas.height <= 628, 'minimum window fits');
    // A separate player profile reviews and confirms the real bulk UI.
    const bulkContext = await browser.newContext({viewport:{width:1440,height:940}});
    const bulkPage = await bulkContext.newPage();
    bulkPage.on('console', m => {
      logs.push('bulk ' + m.type() + ': ' + m.text());
      if (m.type() === 'error' || /SCRIPT ERROR|ERROR:/.test(m.text())) errors.push(m.text());
    });
    bulkPage.on('pageerror', e => errors.push(e.message));
    await openGame(bulkPage);
    await bulkPage.mouse.click(200,431);
    // The separate title creates gameplay on the next engine frame.
    await bulkPage.waitForTimeout(600);
    await press(bulkPage, 'i');
    await bulkPage.waitForTimeout(250);
    await bulkPage.mouse.click(1272,128); // Quality ordering.
    await bulkPage.mouse.click(1200,780); // Review the two normal items.
    await bulkPage.waitForTimeout(250);
    await bulkPage.screenshot({path:path.join(out,'bulk-review.png')});
    await bulkPage.mouse.click(1072,780); // Cancel before any mutation.
    await press(bulkPage, 'i');
    await press(bulkPage, 'Escape');
    await bulkPage.mouse.click(650,308);
    await bulkPage.waitForTimeout(1500);
    const cancelled = await readSave(bulkPage, 'bulk-cancelled');
    check(cancelled.state.gear_items.filter(i=>!i.stock).length === 3 && cancelled.state.reserves.scrap === 48 &&
      cancelled.state.reserves.coal === 32, 'browser bulk cancellation preserves all items and materials');
    await press(bulkPage, 'Escape');
    await press(bulkPage, 'i');
    await bulkPage.waitForTimeout(250);
    await bulkPage.mouse.click(1200,780);
    await bulkPage.waitForTimeout(250);
    await bulkPage.mouse.click(1352,780); // Confirm the reviewed normal items.
    await bulkPage.screenshot({path:path.join(out,'bulk-confirmed.png')});
    await press(bulkPage, 'i');
    await press(bulkPage, 'Escape');
    await bulkPage.mouse.click(650,308);
    await bulkPage.waitForTimeout(1500);
    const salvaged = await readSave(bulkPage, 'bulk-salvaged');
    check(salvaged.state.gear_items.filter(i=>!i.stock).length === 1 && salvaged.state.gear_items[0].uid === 3 &&
      salvaged.state.gear_items[0].rarity === 'uncommon' && salvaged.state.reserves.scrap === 57 &&
      salvaged.state.reserves.coal === 37, 'browser bulk confirmation preserves uncommon equipment and grants exact materials');
    await openGame(bulkPage);
    await bulkPage.mouse.click(200,501);
    await bulkPage.waitForTimeout(1500);
    await press(bulkPage, 'Escape');
    await bulkPage.mouse.click(650,308);
    await bulkPage.waitForTimeout(1500);
    const bulkRestored = await readSave(bulkPage, 'bulk-restored');
    check(JSON.stringify(bulkRestored.state.gear_items) === JSON.stringify(salvaged.state.gear_items) &&
      JSON.stringify(bulkRestored.state.reserves) === JSON.stringify(salvaged.state.reserves),
      'browser reload preserves confirmed bulk salvage without duplicate materials');
    await bulkContext.close();
    check(errors.length === 0, 'no browser or Godot runtime errors: ' + errors.join('\n'));
    fs.writeFileSync(path.join(out,'browser-result.json'), JSON.stringify({base,checks:results.length,failures:0,results,audioPeak,states:{prepared:prepared.state,stationary:stationary.state,moved:moved.state,restored:restored.state},browser:browser.version()},null,2));
    console.log(`WEB RESULT: ${results.length} checks, 0 failures`);
  } finally {
    fs.writeFileSync(path.join(out,'browser-console.log'), logs.join('\n'));
    await browser.close();
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
