// Rebuild public screenshots using only the frontend's synthetic demo.
const {chromium}=require(process.env.PLAYWRIGHT_PATH||'playwright');
const {browserOptions}=require('./fixtures.cjs');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
(async()=>{
 const browser=await chromium.launch(browserOptions());
 try {
  const page=await browser.newPage({viewport:{width:1440,height:1050}});
  let queries=0;
  await page.route('**/api/config',async route=>{
   const response=await route.fetch(),config=await response.json();
   await route.fulfill({json:{...config,preferences:null}});
  });
  await page.route('**/api/query',async route=>{queries++;await route.abort();});
  await page.goto(process.env.TEST_URL||'http://127.0.0.1:18767');
  await page.waitForFunction(()=>document.getElementById('status').textContent.includes('首次使用'));
  assert.equal(await page.locator('#room').inputValue(),'');
  assert.equal(await page.locator('#side-room').textContent(),'选择你的宿舍');
  assert.equal(queries,0);
  await page.locator('#demo').click();
  await page.locator('#data-area').waitFor();
  await page.mouse.move(1300,100);
  const output=path.resolve(__dirname,'../docs/images');fs.mkdirSync(output,{recursive:true});
  await page.screenshot({path:path.join(output,'overview.png'),fullPage:true});
  await page.locator('.nav[data-target="usage-section"]').click();await page.waitForTimeout(600);
  await page.locator('#usage-chart .chart-hit[data-recharges="1"]').last().hover();
  await page.locator('#usage-tooltip').waitFor();
  await page.waitForTimeout(300);
  await page.screenshot({path:path.join(output,'interaction.png')});
  assert.equal(queries,0);
  console.log('PASS: clean first launch makes no school query; screenshots contain synthetic demo only');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
