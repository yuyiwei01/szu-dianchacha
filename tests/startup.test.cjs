const {chromium}=require(process.env.PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict');
const {dorm,mockQueries,saveDorm,browserOptions}=require('./fixtures.cjs');
const base=process.env.TEST_URL||'http://127.0.0.1:18767';
const other=process.env.SECOND_TEST_URL||'http://127.0.0.1:18768';
(async()=>{
 const browser=await chromium.launch(browserOptions());
 try {
  await saveDorm(base);
  const first=await browser.newContext(),a=await first.newPage();await mockQueries(a);
  await a.goto(base);await a.waitForFunction(()=>document.getElementById('status').textContent.includes('查询完成'));
  const saved=a.waitForResponse(r=>r.url().endsWith('/api/preferences')&&r.request().postDataJSON().room==='102');
  await a.locator('#room').fill('102');await saved;
  assert.equal(await a.locator('#side-room').textContent(),'紫薇斋 · 102');await first.close();
  // Another browser context and port have no shared localStorage.
  const second=await browser.newContext(),b=await second.newPage();const requests=await mockQueries(b);
  await b.goto(other);await b.waitForFunction(()=>document.getElementById('status').textContent.includes('查询完成'));
  assert.equal(await b.locator('#side-room').textContent(),'紫薇斋 · 102');
  assert.equal(await b.locator('#room').inputValue(),'102');
  assert.equal(await b.locator('[data-days="30"]').getAttribute('aria-pressed'),'true');
  assert.equal(requests.length,1);assert.equal(requests[0].room,'102');
  assert.equal((Date.parse(requests[0].end)-Date.parse(requests[0].begin))/86400000,29);
  await second.close();
  console.log('PASS: dorm saved without querying, restored across fresh browsers and ports, exactly one automatic 30-day query');
 } finally {await browser.close();await saveDorm(base,dorm)}
})().catch(e=>{console.error(e);process.exitCode=1});
