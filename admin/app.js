import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-app.js';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, onAuthStateChanged, browserSessionPersistence, setPersistence } from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-auth.js';
const config = __FIREBASE_PUBLIC_CONFIG__;
const auth = getAuth(initializeApp(config));
await setPersistence(auth,browserSessionPersistence);
const $=id=>document.getElementById(id), num=n=>Number(n||0).toLocaleString('ar-EG');
let users=[], nextPage='', overview;
function status(message,error=false){$('status').textContent=message;$('status').classList.toggle('error',error);}
async function api(path,body){
  if(!auth.currentUser)throw new Error('سجّل الدخول الأول.');
  const token=await auth.currentUser.getIdToken();
  const response=await fetch('/api/admin/'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+token,...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
  const data=await response.json();if(!response.ok)throw new Error(data.error||'تعذّر تحميل البيانات');return data;
}
async function action(callback){try{status('جاري التنفيذ…');await callback();status('البيانات محدثة.');}catch(error){status(error.message,true);}}
function cell(row,text,cls){const el=document.createElement('td');el.textContent=text;if(cls)el.className=cls;row.append(el);return el;}
function row(parent,values){const el=document.createElement('tr');values.forEach(v=>cell(el,v));parent.append(el);return el;}
function date(ms){return ms?new Date(Number(ms)).toLocaleString('ar-EG'):'—';}
function renderOverview(data){
  overview=data;const totals=data.daily.reduce((a,d)=>{for(const k of ['requests','successes','errors','durationMs','inputTokens','outputTokens'])a[k]=(a[k]||0)+Number(d[k]||0);return a;},{});
  const cost=(totals.inputTokens*data.settings.inputPrice+totals.outputTokens*data.settings.outputPrice)/1e6;
  const cards=[['إجمالي حسابات Firebase',num(data.totalUsers)],['حسابات نشطة اليوم',num(data.activeToday)+(data.activeTodayCapped?'+':'')],['طلبات آخر ٣٠ يومًا',num(totals.requests)],['نسبة الأخطاء',totals.requests?(totals.errors/totals.requests*100).toFixed(1)+'%':'—'],['متوسط وقت السيرفر',totals.requests?(totals.durationMs/totals.requests/1000).toFixed(2)+' ث':'—'],['تكلفة تقديرية للفترة',data.settings.inputPrice||data.settings.outputPrice?'$'+cost.toFixed(4):'غير محددة']];
  cards.splice(2,0,['محادثات محفوظة بالنظام الجديد',data.totalConversations===null?'غير متاح':num(data.totalConversations)],['رسائل محفوظة',data.totalMessages===null?'غير متاح':num(data.totalMessages)]);
  $('cards').replaceChildren();for(const [label,value]of cards){const div=document.createElement('div');div.className='card';const small=document.createElement('small');small.textContent=label;const strong=document.createElement('strong');strong.textContent=value;div.append(small,strong);$('cards').append(div);}
  $('chart').replaceChildren();const max=Math.max(1,...data.daily.map(d=>d.requests||0));for(const d of data.daily){const bar=document.createElement('div');bar.className='bar';bar.style.height=Math.max(2,(d.requests||0)/max*100)+'%';bar.title=d.day+': '+num(d.requests);$('chart').append(bar);}
  $('health').replaceChildren();const p=document.createElement('p');p.textContent=(data.settings.maintenance?'الخدمة في وضع صيانة':'الردود متاحة')+' · '+data.model;$('health').append(p);
  $('daily').replaceChildren();for(const d of [...data.daily].reverse())row($('daily'),[d.day,num(d.requests),num(d.successes),num(d.errors),d.requests?(d.durationMs/d.requests/1000).toFixed(2)+' ث':'—',num(d.inputTokens),num(d.outputTokens)]);
  for(const[k,v]of Object.entries(data.settings)){if($(k)){$(k).type==='checkbox'?$(k).checked=v:$(k).value=v;}}
  $('auditRows').replaceChildren();for(const item of data.audit)row($('auditRows'),[new Date(item.at).toLocaleString('ar-EG'),item.admin,item.action,item.target]);
}
async function loadUsers(page=''){
  const search=$('search').value.trim();const data=await api('users?'+new URLSearchParams(search?{search}:{pageToken:page}));users=data.users;nextPage=data.nextPageToken;
  $('userRows').replaceChildren();for(const user of users){const tr=document.createElement('tr');const name=cell(tr,user.name||'بدون اسم');const id=document.createElement('small');id.textContent=user.uid;name.append(id);cell(tr,user.email||'—','email');cell(tr,user.providers.length?user.providers.join(', '):'ضيف');cell(tr,date(user.createdAt));cell(tr,date(user.lastLoginAt));cell(tr,user.disabled?'معطّل':'متاح');const controls=cell(tr,'');const button=document.createElement('button');button.textContent=user.disabled?'إعادة التفعيل':'تعطيل';button.className=user.disabled?'secondary':'danger';button.disabled=user.uid===auth.currentUser?.uid;button.onclick=()=>{if(confirm((user.disabled?'تفعيل':'تعطيل')+' حساب '+(user.email||user.uid)+'؟'))action(async()=>{await api('user-status',{uid:user.uid,disabled:!user.disabled});await loadUsers(page);renderOverview(await api('overview'));});};controls.append(button);$('userRows').append(tr);}
  if(!users.length)row($('userRows'),['مفيش حسابات مطابقة.']);$('next').hidden=!nextPage;
}
$('signIn').onclick=()=>action(async()=>{const provider=new GoogleAuthProvider();provider.setCustomParameters({prompt:'select_account'});await signInWithPopup(auth,provider);});
$('logout').onclick=()=>signOut(auth);
onAuthStateChanged(auth,async user=>{
  $('identity').textContent=user?.email||'';$('logout').hidden=!user;
  $('dashboard').hidden=true;$('login').hidden=false;
  if(user){await action(async()=>{renderOverview(await api('overview'));await loadUsers();$('dashboard').hidden=false;$('login').hidden=true;});}
});
for(const button of document.querySelectorAll('[data-tab]'))button.onclick=()=>{for(const tab of document.querySelectorAll('.tab'))tab.hidden=tab.id!==button.dataset.tab;for(const b of document.querySelectorAll('[data-tab]'))b.classList.toggle('active',b===button);};
$('refresh').onclick=()=>action(async()=>{renderOverview(await api('overview'));await loadUsers();});
$('searchForm').onsubmit=e=>{e.preventDefault();action(()=>loadUsers());};
$('clearSearch').onclick=()=>{$('search').value='';action(()=>loadUsers());};
$('next').onclick=()=>action(()=>loadUsers(nextPage));
$('settingsForm').onsubmit=e=>{e.preventDefault();const data={};for(const[k,v]of Object.entries(overview.settings)){data[k]=typeof v==='boolean'?$(k).checked:typeof v==='number'?Number($(k).value):$(k).value;}if(confirm('تطبيق الإعدادات الجديدة على الخدمة؟'))action(async()=>{await api('settings',data);renderOverview(await api('overview'));});};
$('export').onclick=()=>{
  // Prevent spreadsheet formula execution in names/emails supplied by accounts.
  const csv=v=>{
    const text=String(v??'');
    const safe=/^\s*[=+@-]/.test(text)||/^[\t\r\n]/.test(text)?"'"+text:text;
    return '"'+safe.replace(/"/g,'""')+'"';
  };
  const lines=[['UID','Email','Name','Disabled','Created','Last login'],...users.map(u=>[u.uid,u.email,u.name,u.disabled,new Date(u.createdAt).toISOString(),u.lastLoginAt?new Date(u.lastLoginAt).toISOString():''])];
  const url=URL.createObjectURL(new Blob(['\ufeff'+lines.map(r=>r.map(csv).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}));const link=document.createElement('a');link.href=url;link.download='maalish-users-current-page.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
};
