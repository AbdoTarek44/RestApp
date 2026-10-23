import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-app.js';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, onAuthStateChanged, browserSessionPersistence, setPersistence } from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-auth.js';
const config = __FIREBASE_PUBLIC_CONFIG__;
const auth = getAuth(initializeApp(config));
await setPersistence(auth,browserSessionPersistence);
const $=id=>document.getElementById(id), num=n=>Number(n||0).toLocaleString('ar-EG');
let users=[], nextPage='', overview, insightData, notificationDraft;
let sendingNotification=false;
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
  const cards=[['إجمالي حسابات Firebase',num(data.totalUsers)],['حسابات نشطة اليوم',num(data.activeToday)+(data.activeTodayCapped?'+':'')],['طلبات الفترة المختارة',num(totals.requests)],['نسبة الأخطاء',totals.requests?(totals.errors/totals.requests*100).toFixed(1)+'%':'—'],['متوسط وقت السيرفر',totals.requests?(totals.durationMs/totals.requests/1000).toFixed(2)+' ث':'—'],['تكلفة تقديرية للفترة',data.settings.inputPrice||data.settings.outputPrice?'$'+cost.toFixed(4):'غير محددة']];
  cards.splice(2,0,['محادثات محفوظة بالنظام الجديد',data.totalConversations===null?'غير متاح':num(data.totalConversations)],['رسائل محفوظة',data.totalMessages===null?'غير متاح':num(data.totalMessages)]);
  $('cards').replaceChildren();for(const [label,value]of cards){const div=document.createElement('div');div.className='card';const small=document.createElement('small');small.textContent=label;const strong=document.createElement('strong');strong.textContent=value;div.append(small,strong);$('cards').append(div);}
  renderActivityChart(data.daily);
  $('health').replaceChildren();const grid=document.createElement('div');grid.className='health-grid';
  for(const [label,value]of [['الخدمة',data.settings.maintenance?'صيانة مؤقتة':'الردود متاحة'],['الموديل',data.model],['خصوصية الكلام','غير متاح للإدارة']]){
    const item=document.createElement('div');item.className='health-item';const labelEl=document.createElement('span');labelEl.textContent=label;const valueEl=document.createElement('strong');valueEl.textContent=value;item.append(labelEl,valueEl);grid.append(item);
  }$('health').append(grid);
  $('daily').replaceChildren();for(const d of [...data.daily].reverse())row($('daily'),[d.day,num(d.requests),num(d.successes),num(d.errors),d.requests?(d.durationMs/d.requests/1000).toFixed(2)+' ث':'—',num(d.inputTokens),num(d.outputTokens)]);
  for(const[k,v]of Object.entries(data.settings)){if($(k)){$(k).type==='checkbox'?$(k).checked=v:$(k).value=v;}}
  $('auditRows').replaceChildren();for(const item of data.audit)row($('auditRows'),[new Date(item.at).toLocaleString('ar-EG'),item.admin,item.action,item.target]);
}
async function loadUsers(page=''){
  const search=$('search').value.trim();const data=await api('users?'+new URLSearchParams(search?{search}:{pageToken:page}));users=data.users;nextPage=data.nextPageToken;
  $('userRows').replaceChildren();for(const user of users){const tr=document.createElement('tr');const name=cell(tr,user.name||'بدون اسم');const id=document.createElement('small');id.textContent=user.uid;name.append(id);cell(tr,user.email||'—','email');cell(tr,user.providers.length?user.providers.join(', '):'ضيف');cell(tr,date(user.createdAt));cell(tr,date(user.lastLoginAt));cell(tr,user.disabled?'معطّل':'متاح');const controls=cell(tr,'');const button=document.createElement('button');button.textContent=user.disabled?'إعادة التفعيل':'تعطيل';button.className=user.disabled?'secondary':'danger';button.disabled=user.uid===auth.currentUser?.uid;button.onclick=()=>{if(confirm((user.disabled?'تفعيل':'تعطيل')+' حساب '+(user.email||user.uid)+'؟'))action(async()=>{await api('user-status',{uid:user.uid,disabled:!user.disabled});await loadUsers(page);renderOverview(await api('overview?'+rangeParams()));});};controls.append(button);
    const notify=document.createElement('button');notify.textContent='إشعار';notify.className='secondary';notify.style.marginRight='6px';notify.onclick=()=>{$('notificationTarget').value='user';$('notificationUid').value=user.uid;updateTarget();switchTab('notifications');};controls.append(notify);
    $('userRows').append(tr);}
  if(!users.length)row($('userRows'),['مفيش حسابات مطابقة.']);$('next').hidden=!nextPage;
}
async function login(){const provider=new GoogleAuthProvider();provider.setCustomParameters({prompt:'select_account'});await signInWithPopup(auth,provider);}
$('signIn').onclick=()=>action(login);
$('reauth').onclick=()=>action(async()=>{await login();await loadAll();});
$('logout').onclick=()=>signOut(auth);
onAuthStateChanged(auth,async user=>{
  $('identity').textContent=user?.email||'';$('logout').hidden=!user;$('reauth').hidden=!user;document.body.classList.remove('signed-in');
  $('dashboard').hidden=true;$('login').hidden=false;
  if(user){await action(async()=>{await loadAll();await loadUsers();$('dashboard').hidden=false;$('login').hidden=true;document.body.classList.add('signed-in');});}
});
for(const button of document.querySelectorAll('[data-tab]'))button.onclick=()=>switchTab(button.dataset.tab);
$('refresh').onclick=()=>action(async()=>{await loadAll();await loadUsers();});
$('searchForm').onsubmit=e=>{e.preventDefault();action(()=>loadUsers());};
$('clearSearch').onclick=()=>{$('search').value='';action(()=>loadUsers());};
$('next').onclick=()=>action(()=>loadUsers(nextPage));
$('settingsForm').onsubmit=e=>{e.preventDefault();const data={};for(const[k,v]of Object.entries(overview.settings)){data[k]=typeof v==='boolean'?$(k).checked:typeof v==='number'?Number($(k).value):$(k).value;}if(confirm('تطبيق الإعدادات الجديدة على الخدمة؟'))action(async()=>{await api('settings',data);renderOverview(await api('overview?'+rangeParams()));});};
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

const topicLabels={marriage:'الزواج',family:'الأسرة',relatives:'الأقارب',parenting:'الأبناء والتربية',relationship:'العلاقات',friends:'الصحاب',work:'الشغل',money:'الفلوس',study:'الدراسة',grief:'الفقد',loneliness:'الوحدة',self_confidence:'الثقة بالنفس',future:'المستقبل',decision:'القرارات',health_concern:'مخاوف صحية',daily_life:'ضغوط يومية',other:'مواضيع تانية'};
const moodLabels={angry:'متنرفز',stressed:'مضغوط',sad:'زعلان',anxious:'قلقان',lonely:'حاسس بوحدة',neutral:'عادي',other:'شعور تاني',skip:'بدون اختيار'};
const outcomeLabels={same:'زي ما أنا',lighter:'أخف شوية',better:'أحسن',good:'تمام',skip:'بدون تقييم'};
const tabLabels={overview:['نظرة عامة','الصورة الكاملة لتشغيل معلش ونشاط الحسابات.'],insights:['فهم الفضفضات','تصنيفات عامة وتقييمات اختيارية تساعدك تفهم التجربة.'],users:['المستخدمون','الحسابات المسجّلة وإدارة وصولها للتطبيق.'],notifications:['الإشعارات','رسالة قصيرة، بمعاينة واضحة وتأكيد قبل الإرسال.'],settings:['إعدادات التطبيق','تحكّم في التشغيل وشكل التجربة من مكان واحد.'],audit:['سجل الإدارة','سجل واضح لتغييرات الحسابات والإعدادات والإشعارات.']};
function switchTab(id){for(const tab of document.querySelectorAll('.tab'))tab.hidden=tab.id!==id;for(const b of document.querySelectorAll('[data-tab]'))b.classList.toggle('active',b.dataset.tab===id);$('pageTitle').textContent=tabLabels[id][0];$('pageSubtitle').textContent=tabLabels[id][1];}
function setPreset(){const days=Number($('rangePreset').value);if(!days)return;const end=new Date();$('rangeTo').value=end.toISOString().slice(0,10);$('rangeFrom').value=new Date(Date.parse($('rangeTo').value+'T00:00:00Z')-(days-1)*86400000).toISOString().slice(0,10);}
function rangeParams(){const from=$('rangeFrom').value,to=$('rangeTo').value;const delta=Date.parse(to)-Date.parse(from);if(!from||!to||delta<0||delta>=90*86400000)throw new Error('اختار مدة صحيحة لا تزيد عن ٩٠ يومًا.');return new URLSearchParams({from,to}).toString();}
$('rangePreset').onchange=setPreset;setPreset();
$('applyRange').onclick=()=>action(loadAll);
async function loadAll(){const range=rangeParams();const [data,insights]=await Promise.all([api('overview?'+range),api('insights?'+range)]);renderOverview(data);renderInsights(insights);$('chartStart').textContent=$('rangeFrom').value;$('chartEnd').textContent=$('rangeTo').value;if(!data.daily.length)empty($('chart'),'الإحصائيات هتظهر مع أول طلب رد خلال الفترة.');await loadNotifications();}
function empty(element,message){element.replaceChildren();const text=document.createElement('div');text.className='empty';text.textContent=message;element.append(text);}
function renderActivityChart(daily){
 const chart=$('chart');chart.replaceChildren();
 const from=Date.parse($('rangeFrom').value+'T00:00:00Z'),until=Date.parse($('rangeTo').value+'T00:00:00Z');
 const known=new Map(daily.map(d=>[d.day,Number(d.requests||0)])),days=[];
 for(let t=from;t<=until;t+=86400000){const day=new Date(t).toISOString().slice(0,10);days.push({day,count:known.get(day)||0});}
 if(!days.some(d=>d.count)){empty(chart,'الإحصائيات هتظهر مع أول طلب رد خلال الفترة.');return;}
 const size=days.length>45?3:1,buckets=[];
 for(let i=0;i<days.length;i+=size){const group=days.slice(i,i+size);buckets.push({label:group[0].day+(group.length>1?' — '+group.at(-1).day:''),count:group.reduce((a,d)=>a+d.count,0)});}
 const max=Math.max(1,...buckets.map(v=>v.count));
 for(const item of buckets){const bar=document.createElement('div');bar.className='bar';bar.style.height=item.count?item.count/max*100+'%':'2px';if(!item.count)bar.style.background='#dce6ec';bar.title=item.label+': '+num(item.count);chart.append(bar);}
}
function cards(element,values){element.replaceChildren();for(const[label,value,note]of values){const card=document.createElement('div');card.className='card';const small=document.createElement('small');small.textContent=label;const strong=document.createElement('strong');strong.textContent=value;card.append(small,strong);if(note){const em=document.createElement('em');em.textContent=note;card.append(em);}element.append(card);}}
function ranks(element,buckets,labels){element.replaceChildren();const sorted=Object.entries(buckets).filter(([,v])=>v.sessions>0).sort((a,b)=>b[1].sessions-a[1].sessions);if(!sorted.length){empty(element,'لسه مفيش مشاركات كفاية في الفترة دي.');return;}const max=Math.max(...sorted.map(([,v])=>v.sessions));for(const[key,value]of sorted){const line=document.createElement('div');line.className='rank-row';const label=document.createElement('span');label.textContent=labels[key]||key;const track=document.createElement('div');track.className='rank-track';const fill=document.createElement('div');fill.className='rank-fill';fill.style.width=(value.sessions/max*100)+'%';track.append(fill);const count=document.createElement('span');count.className='rank-value';count.textContent=num(value.sessions)+' جلسة · '+num(value.users)+' حساب';line.append(label,track,count);element.append(line);}}
function renderInsights(data){
 insightData=data;
 cards($('insightCards'),[['جلسات مشاركة',num(data.started),'اللي أصحابها وافقوا على التحليل'],['حسابات مشاركة',num(data.participants),'حسابات فريدة خلال الفترة'],['تقييمات نهاية',num(data.rated),'مقام نسبة التقييم الإيجابي'],['تقييم نهاية إيجابي',data.improvementRate===null?'—':(data.improvementRate*100).toFixed(1)+'%',num(data.improved)+' من '+num(data.rated)+' تقييم']]);
 $('insightNotice').textContent='التحليلات دي من المشاركات الاختيارية في النسخة الجديدة، ومش بتمثّل كل المستخدمين. '+num(data.noCompletion)+' جلسة بدون إنهاء مسجّل، و'+num(data.unratedCompleted)+' انتهت بدون تقييم.'+(data.capped?' النتيجة محدودة بأول '+num(data.limit)+' جلسة؛ قلّل الفترة لتحليل أدق.':'');
 ranks($('topicRanks'),data.topics,topicLabels);ranks($('beforeRanks'),data.before,moodLabels);
 $('outcomes').replaceChildren();for(const[key,label]of Object.entries(outcomeLabels)){const item=document.createElement('div');item.className='outcome-row';const title=document.createElement('span');const dot=document.createElement('i');dot.className='outcome-dot';dot.style.background={same:'#d1a37b',lighter:'#a0bca5',better:'#57a198',good:'#278678',skip:'#c4cdd6'}[key];title.append(dot,document.createTextNode(label));const value=document.createElement('strong');value.textContent=num(data.after[key]);item.append(title,value);$('outcomes').append(item);}
 $('moodMatrix').replaceChildren();for(const[key,label]of Object.entries(moodLabels)){const tr=row($('moodMatrix'),[label,...['same','lighter','better','good'].map(v=>num(data.matrix[key+'_'+v]||0))]);for(let i=1;i<tr.children.length;i++){const value=Number(data.matrix[key+'_'+['same','lighter','better','good'][i-1]]||0);if(value)tr.children[i].style.background='rgba(74,148,138,'+Math.min(.3,.07+value/Math.max(1,data.rated)) +')';}}
 $('insightDaily').replaceChildren();for(const d of [...data.daily].reverse())row($('insightDaily'),[d.day,num(d.started),num(d.completed),num(d.rated),num(d.improved)]);
 if(!data.daily.length)row($('insightDaily'),['لسه مفيش مشاركات في الفترة المختارة.']);
}
function downloadCsv(filename,lines){const safe=v=>{const s=String(v??'');return '"'+(/^\s*[=+@-]/.test(s)||/^[\t\r\n]/.test(s)?"'"+s:s).replace(/"/g,'""')+'"';};const url=URL.createObjectURL(new Blob(['\ufeff'+lines.map(r=>r.map(safe).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
$('exportInsights').onclick=()=>{if(!insightData)return;const d=insightData;downloadCsv('maalish-aggregate-insights.csv',[['الفترة',d.from,d.to],['المؤشر','عدد الجلسات أو القيمة','حسابات فريدة عند انطباقها'],['جلسات مشاركة',d.started],['حسابات مشاركة',d.participants],['تقييمات نهاية',d.rated],['تقييمات أخف أو أحسن',d.improved],['بدون إنهاء مسجل',d.noCompletion],['بدون تقييم نهاية',d.unratedCompleted],...Object.entries(d.topics).map(([k,v])=>['موضوع: '+topicLabels[k],v.sessions,v.users]),...Object.entries(d.before).map(([k,v])=>['شعور قبل: '+moodLabels[k],v.sessions,v.users]),...Object.entries(d.after).map(([k,v])=>['تقييم بعد: '+outcomeLabels[k],v])]);};
function updateTarget(){$('notificationUidLabel').hidden=$('notificationTarget').value!=='user';$('notificationUid').required=$('notificationTarget').value==='user';}
$('notificationTarget').onchange=updateTarget;
for(const id of ['notificationTitle','notificationBody'])$(id).oninput=()=>{$('liveTitle').textContent=$('notificationTitle').value||'عنوان الإشعار هيظهر هنا';$('liveBody').textContent=$('notificationBody').value||'ورسالتك هتظهر بالشكل ده على الجهاز.';$('titleCounter').textContent=num($('notificationTitle').value.length)+' / ٧٠';$('bodyCounter').textContent=num($('notificationBody').value.length)+' / ١٨٠';};
async function loadNotifications(){const result=await api('notifications');$('pushDevices').textContent=num(result.devices)+(result.devicesCapped?'+':'')+' جهاز مسجّل ومفعّل';$('campaignRows').replaceChildren();const labels={draft:'مسودة',sending:'بدأ الإرسال',accepted:'قبلته Google',partial:'قبول جزئي',failed:'تعذّر الإرسال',unknown:'النتيجة غير مؤكدة'};for(const c of result.campaigns){const tr=document.createElement('tr');cell(tr,date(c.createdAt));const content=cell(tr,c.title);const text=document.createElement('small');text.textContent=c.body;content.append(text);cell(tr,c.target==='all'?'كل الأجهزة المفعّلة':c.uid);cell(tr,num(c.registeredDevices));const state=cell(tr,'');const tag=document.createElement('span');tag.className='tag';tag.textContent=labels[c.status]||c.status;state.append(tag);cell(tr,num(c.accepted));$('campaignRows').append(tr);}if(!result.campaigns.length)row($('campaignRows'),['لسه مفيش إشعارات أو مسودات.']);}
$('refreshNotifications').onclick=()=>action(loadNotifications);
$('notificationForm').onsubmit=e=>{e.preventDefault();if(sendingNotification)return;action(async()=>{
 $('previewNotification').disabled=true;
 try{notificationDraft=await api('notifications/preview',{title:$('notificationTitle').value,body:$('notificationBody').value,target:$('notificationTarget').value,uid:$('notificationUid').value.trim()});$('confirmTitle').textContent=notificationDraft.title;$('confirmBody').textContent=notificationDraft.body;$('confirmAudience').textContent=(notificationDraft.target==='all'?'إلى كل الأجهزة المفعّلة':'إلى حساب '+notificationDraft.uid)+' · '+num(notificationDraft.registeredDevices)+' جهاز مسجّل. العدد مش ضمان للاستلام.';$('confirmSend').disabled=!notificationDraft.registeredDevices;$('notificationDialog').showModal();}
 finally{$('previewNotification').disabled=false;}
});};
$('cancelSend').onclick=()=>{if(!sendingNotification)$('notificationDialog').close();};
$('notificationDialog').addEventListener('cancel',event=>{if(sendingNotification)event.preventDefault();});
$('confirmSend').onclick=async()=>{
 if(!notificationDraft||sendingNotification)return;sendingNotification=true;$('confirmSend').disabled=true;$('cancelSend').disabled=true;
 try{status('جاري إرسال الطلب إلى Google…');const result=await api('notifications/send',{campaignId:notificationDraft.id,confirm:true});$('notificationDialog').close();await loadNotifications();status(result.status==='accepted'?'Google قبلت طلب الإرسال. الاستلام والقراءة مش مؤكّدين.':result.status==='unknown'||result.status==='sending'?'نتيجة الإرسال غير مؤكدة. راجع السجل قبل إنشاء طلب جديد.':'تم تحديث نتيجة الإرسال في السجل.');}
 catch(error){status('نتيجة الإرسال غير مؤكدة: '+error.message+' حدّث السجل قبل إرسال نفس الرسالة من جديد.',true);$('notificationDialog').close();}
 finally{sendingNotification=false;$('cancelSend').disabled=false;}
};
