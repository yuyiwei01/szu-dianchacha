// Synthetic records only: browser tests never query the school.
const assert = require('node:assert/strict');
const dorm = {campus:'新斋区',building:'紫薇斋',room:'101'};
function fixture(request) {
 const usage=[],purchases=[];let used=1000,bought=1200;
 for(let day=Date.parse(request.begin),i=0;day<=Date.parse(request.end);day+=86400000,i++) {
  const date=new Date(day).toISOString().slice(0,10);used+=4.3+Math.sin(i*.51)*1.5;
  if(i%20===10){bought+=142.86;purchases.push({no:purchases.length+1,room:request.room,date:date+' 12:35:20',amount:142.86,money:100,buyType:'微信购电',buyer:'演示用户'});}
  usage.push({no:usage.length+1,room:request.room,date:date+' 23:59:00',remain:+(bought-used).toFixed(2),used:+used.toFixed(2),bought});
 }
 return {...request,usage,purchases,complete:true,usagePages:Math.ceil(usage.length/20),purchasePages:Math.ceil(purchases.length/20),fetchedAt:'模拟测试'};
}
async function mockQueries(page) {
 const requests=[];let job={state:'idle'};
 await page.route('**/api/query',async route=>{
  const request=route.request().postDataJSON();requests.push(request);
  if(request.room==='ZZ-NO-ROOM'){await route.fulfill({status:400,json:{message:'没有找到该房间。'}});return;}
  const id='fixture-'+requests.length;job={id,state:'done',data:fixture(request)};
  await route.fulfill({status:202,json:{id,state:'running'}});
 });
 await page.route('**/api/job',route=>route.fulfill({json:job}));return requests;
}
async function saveDorm(base,value=dorm) {
 const config=await(await fetch(base+'/api/config')).json();
 const response=await fetch(base+'/api/preferences',{method:'POST',headers:{'Content-Type':'application/json','X-Local-Token':config.token},body:JSON.stringify(value)});assert.equal(response.status,200);
}
function browserOptions(){return {headless:true,...(process.env.BROWSER_CHANNEL?{channel:process.env.BROWSER_CHANNEL}:{})};}
module.exports={dorm,fixture,mockQueries,saveDorm,browserOptions};
