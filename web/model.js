export const dayKey = row => row.date.slice(0, 10);
export const utcDay = date => Date.parse(date.slice(0,10) + 'T00:00:00Z') / 86400000;
export function analyzeUsage(rows) {
  const ordered = [...rows].sort((a,b) => a.date.localeCompare(b.date) || a.no-b.no);
  const byDay = new Map();
  for (const row of ordered) byDay.set(dayKey(row), row);
  const snapshots = [...byDay.values()];
  let used = 0, days = 0, resets = 0, gaps = 0;
  const intervals = snapshots.map((row, i) => {
    const previous = snapshots[i-1];
    if (!previous) return {...row, delta:null, daily:null, span:0, from:null, fromDate:null};
    const span = utcDay(row.date) - utcDay(previous.date), delta = row.used-previous.used;
    if (delta < 0) { resets++; return {...row,delta:null,daily:null,span,from:dayKey(previous),fromDate:previous.date,reset:true}; }
    if (span > 1) gaps++;
    used += delta; days += span;
    return {...row,delta,daily:delta/span,span,from:dayKey(previous),fromDate:previous.date};
  });
  const latest = snapshots.at(-1) || null;
  const average = days ? used/days : null;
  const estimate = average > 0 && latest ? Math.max(0,latest.remain)/average : null;
  return {latest,average,estimate,used,days,resets,gaps,intervals};
}
export function estimateTariff(purchases, override='') {
  if (String(override).trim() !== '') {
    const value=Number(override);
    if(Number.isFinite(value)&&value>=0&&value<=100)return {rate:value,source:'manual'};
  }
  const paid=purchases.filter(r=>r.money>0&&r.amount>0);
  const amount=paid.reduce((s,r)=>s+r.amount,0);
  return {rate:amount?paid.reduce((s,r)=>s+r.money,0)/amount:null,source:'purchases'};
}
export function intervalDetails(interval,purchases,rate) {
  const recharges=interval.fromDate?purchases.filter(p=>p.date>interval.fromDate&&p.date<=interval.date).sort((a,b)=>a.date.localeCompare(b.date)||a.no-b.no):[];
  return {recharges,rechargeTotal:recharges.reduce((s,r)=>s+r.money,0),cost:rate!==null&&interval.delta!==null?interval.delta*rate:null};
}
export function selectRows(data, tab, search='', buyType='', direction='desc') {
  const q=search.trim().toLowerCase();
  return [...(tab==='usage'?data.usage:data.purchases)].filter(r =>
    (!buyType || tab==='usage' || r.buyType===buyType) &&
    (!q || Object.values(r).some(v=>String(v).toLowerCase().includes(q)))
  ).sort((a,b)=>(a.date.localeCompare(b.date)||a.no-b.no)*(direction==='asc'?1:-1));
}
export function csvText(headers, rows) {
  const cell = value => {
    let text = String(value ?? '');
    if (/^[\s]*[=+@\-]/.test(text)) text="'"+text;
    return '"'+text.replaceAll('"','""')+'"';
  };
  return '\ufeff'+[headers,...rows].map(row=>row.map(cell).join(',')).join('\r\n');
}
