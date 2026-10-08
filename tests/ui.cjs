const {chromium}=require(process.env.PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict');
const {mockQueries,saveDorm,browserOptions}=require('./fixtures.cjs');
const base=process.env.TEST_URL||'http://127.0.0.1:18767';
(async()=>{
 const browser=await chromium.launch(browserOptions());
 const context=await browser.newContext({viewport:{width:1440,height:1100},acceptDownloads:true});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 try{
  await saveDorm(base);await mockQueries(page);await page.goto(base);
  await page.locator('#campus option').first().waitFor({state:'attached'});
  await page.waitForFunction(()=>document.getElementById('status').textContent.includes('查询完成'),{},{timeout:60000});
  assert.equal(await page.locator('#side-room').textContent(),'紫薇斋 · 101');
  assert.equal(await page.locator('#remain-section').isVisible(),true);assert.equal(await page.locator('#usage-section').isVisible(),true);
  assert.ok(await page.locator('#remain-chart .line-segment').count()>0);
  for(const target of ['remain-section','usage-section','records-section','overview-section']){await page.locator(`.nav[data-target="${target}"]`).first().click();await page.waitForTimeout(550);const y=await page.locator('#'+target).evaluate(e=>e.getBoundingClientRect().top);assert.ok(y>=0&&y<45,`${target} scroll position ${y}`)}
  await page.locator('.nav[data-record-tab="purchases"]').click();await page.waitForTimeout(550);assert.equal(await page.locator('.record-tabs [data-tab="purchases"]').getAttribute('aria-selected'),'true');await page.locator('.nav[data-record-tab="usage"]').click();
  assert.equal(await page.locator('#advanced-toggle').getAttribute('aria-expanded'),'false');assert.equal(await page.locator('[data-days="30"]').getAttribute('aria-pressed'),'true');
  assert.equal(await page.locator('#advanced-filters').isVisible(),false);
  await page.locator('[data-days="7"]').click();assert.equal(await page.locator('[data-days="7"]').getAttribute('aria-pressed'),'true');await page.locator('[data-days="30"]').click();
  await page.locator('#demo').click();await page.locator('#data-area').waitFor();
  assert.equal(await page.locator('#connection').textContent(),'演示模式');
  assert.ok(await page.locator('#usage-chart .line-segment').count()>20);assert.equal(await page.locator('#usage-scrollbar').isVisible(),true);
  const recharge=page.locator('#usage-chart .chart-hit[data-recharges="1"]').last();await recharge.hover();await page.locator('#usage-tooltip').waitFor();assert.match(await page.locator('#usage-tooltip').textContent(),/演示用户/);assert.equal(await page.locator('#usage-tooltip .avatar').count(),1);assert.match(await page.locator('#usage-tooltip').textContent(),/¥100.00/);
  await page.locator('#tariff').fill('0.5');assert.match(await page.locator('#usage-tariff-note').textContent(),/手动电价 0.5000/);await page.locator('#tariff').fill('');
  await page.locator('#usage-scroll').evaluate(e=>{e.value=0;e.dispatchEvent(new Event('input',{bubbles:true}))});await page.waitForTimeout(100);assert.equal(await page.locator('#usage-viewport').evaluate(e=>e.scrollLeft),0);assert.equal(await page.locator('#usage-tooltip').isVisible(),false);
  await page.locator('.record-tabs [data-tab="purchases"]').click();assert.equal(await page.locator('#table-body tr').count(),2);
  await page.locator('#search').fill('不存在');assert.match(await page.locator('#table-body').textContent(),/没有匹配/);await page.locator('#search').fill('');
  const downloadEvent=page.waitForEvent('download');await page.locator('#export').click();const dl=await downloadEvent;assert.ok(dl.suggestedFilename().startsWith('演示_'));
  await page.locator('#advanced-toggle').click();const end=new Date().toISOString().slice(0,10),begin=new Date(Date.parse(end)-59*86400000).toISOString().slice(0,10);await page.locator('#begin').fill(begin);await page.locator('#end').fill(end);await page.locator('#advanced-toggle').click();await page.locator('#query').click();
  await page.waitForFunction(()=>document.getElementById('status').textContent.includes('查询完成'),{},{timeout:60000});
  assert.equal(await page.locator('#usage-count').textContent(),'60');assert.equal(await page.locator('#purchase-count').textContent(),'3');assert.equal(await page.locator('#spending').textContent(),'300.00');
  await page.locator('.record-tabs [data-tab="usage"]').click();assert.equal(await page.locator('#table-body tr').count(),12);await page.locator('#next').click();assert.equal(await page.locator('#page-info').textContent(),'2 / 5');
  await page.locator('#sort').selectOption('asc');assert.match(await page.locator('#table-body tr').first().textContent(),new RegExp(begin));
  await page.locator('#sort').selectOption('desc');await page.evaluate(()=>window.scrollTo(0,0));
  assert.ok(await page.locator('#remain-chart path').count()>0);
  await page.reload();await page.waitForFunction(()=>document.getElementById('status').textContent.includes('查询完成'),{},{timeout:60000});assert.equal(await page.locator('#connection').textContent(),'本地查询');assert.equal(await page.locator('[data-days="30"]').getAttribute('aria-pressed'),'true');
  await page.setViewportSize({width:390,height:844});await page.waitForTimeout(250);await page.evaluate(()=>window.scrollTo(0,0));
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth);assert.equal(overflow,false);
  await page.locator('#usage-chart .chart-hit[data-recharges="1"]').last().click();await page.locator('#usage-tooltip').waitFor();const card=await page.locator('#usage-tooltip').boundingBox();assert.ok(card.x>=0&&card.x+card.width<=390);await page.keyboard.press('Escape');assert.equal(await page.locator('#usage-tooltip').isVisible(),false);
  await page.setViewportSize({width:1440,height:1100});await page.locator('#room').fill('ZZ-NO-ROOM');await page.locator('#query').click();await page.waitForFunction(()=>document.querySelector('.status-line').classList.contains('error'),{},{timeout:60000});assert.match(await page.locator('#status').textContent(),/没有找到/);
  await page.locator('#room').fill('101');await page.waitForTimeout(500);assert.deepEqual(errors,[]);console.log('PASS: auto startup query, immediate remembered dorm, split charts, sidebar navigation, recharge tooltips, sliders, CSV, mobile; no page errors');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
