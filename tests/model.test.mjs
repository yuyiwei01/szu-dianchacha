import test from 'node:test';
import assert from 'node:assert/strict';
import {analyzeUsage,selectRows,csvText,estimateTariff,intervalDetails} from '../web/model.js';
const r=(no,date,used,remain=100)=>({no,date:date+' 23:59:00',used,remain,room:'101',bought:1000});
test('consumption uses cumulative differences, handles gaps and meter resets',()=>{
 const a=analyzeUsage([r(4,'2026-09-05',2),r(1,'2026-09-01',100),r(2,'2026-09-02',110),r(3,'2026-09-04',130),r(5,'2026-09-06',7)]);
 assert.equal(a.used,35);assert.equal(a.days,4);assert.equal(a.average,8.75);assert.equal(a.resets,1);assert.equal(a.gaps,1);assert.equal(a.intervals[2].daily,10);assert.equal(a.intervals[3].delta,null);
});
test('electricity estimates exclude subsidies and allow explicit zero or manual rates',()=>{
 const purchases=[{money:100,amount:142.86},{money:40,amount:57.14},{money:0,amount:50},{money:100,amount:0}];
 assert.equal(estimateTariff(purchases).rate,.7);assert.equal(estimateTariff([]).rate,null);assert.equal(estimateTariff([],0).rate,0);assert.equal(estimateTariff(purchases,'0.5').rate,.5);
});
test('recharges attach to exact reading intervals once, preserve duplicate purchases and exclude later purchases',()=>{
 const interval={fromDate:'2026-09-01 23:59:00',date:'2026-09-04 23:59:00',delta:30};
 const purchases=[{no:1,date:'2026-09-01 23:59:00',money:100},{no:2,date:'2026-09-03 12:00:00',money:40},{no:3,date:'2026-09-03 12:00:00',money:50},{no:4,date:'2026-09-04 23:59:00',money:0},{no:5,date:'2026-09-05 12:00:00',money:100}];
 const d=intervalDetails(interval,purchases,.7);assert.deepEqual(d.recharges.map(p=>p.no),[2,3,4]);assert.equal(d.rechargeTotal,90);assert.equal(d.cost,21);assert.equal(intervalDetails(interval,purchases,null).cost,null);assert.equal(intervalDetails({...interval,delta:null},purchases,.7).cost,null);
});
test('same day uses the final snapshot, empty and single day do not estimate',()=>{
 assert.equal(analyzeUsage([]).latest,null);assert.equal(analyzeUsage([r(1,'2026-09-01',100)]).estimate,null);
 const a=analyzeUsage([r(1,'2026-09-01',100),{...r(2,'2026-09-01',110),date:'2026-09-01 23:59:59'},r(3,'2026-09-02',120)]);
 assert.equal(a.used,10);assert.equal(a.intervals.length,2);
});
test('purchase filtering preserves distinct purchases with identical dates',()=>{
 const data={usage:[],purchases:[{no:1,date:'2026-09-01 12:00:00',buyer:'甲',buyType:'微信',money:100},{no:2,date:'2026-09-01 12:00:00',buyer:'乙',buyType:'微信',money:100},{no:3,date:'2026-09-02 12:00:00',buyer:'乙',buyType:'补助',money:0}]};
 assert.equal(selectRows(data,'purchases','','微信').length,2);assert.equal(selectRows(data,'purchases','乙','微信')[0].no,2);assert.equal(selectRows(data,'purchases','','','desc')[0].no,3);
});
test('CSV quotes cells, preserves Chinese and neutralizes spreadsheet formulas',()=>{
 const text=csvText(['购买者','金额'],[['=HYPERLINK("x")',100],['张,三',0],['  @SUM(1)',20]]);
 assert.ok(text.startsWith('\ufeff'));assert.ok(text.includes('"\'=HYPERLINK(""x"")"'));assert.ok(text.includes('"张,三"'));assert.ok(text.includes("'  @SUM(1)"));
});
