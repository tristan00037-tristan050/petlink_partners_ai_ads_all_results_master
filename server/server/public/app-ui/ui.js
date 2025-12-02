// Client-only UI helpers (no framework)

export const tokens = { brand:'rgb(var(--c-brand))', accent:'rgb(var(--c-accent))' };

export function toast(msg, type='info'){ // NN/g: immediate feedback
  let el = document.getElementById('app-toast');
  if(!el){ el = document.createElement('div'); el.id='app-toast'; el.className='toast'; document.body.appendChild(el); }
  el.textContent = msg; el.classList.add('show');
  el.style.borderColor = type==='error' ? '#DC2626' : 'var(--c-border)';
  setTimeout(()=> el.classList.remove('show'), 2500);
}

export function withAuth(fetchImpl=fetch){
  const pickToken = () => localStorage.getItem('app_access') || localStorage.getItem('app_access_token') || localStorage.getItem('access_token');
  
  async function call(url, opts={}){
    const headers = new Headers(opts.headers||{});
    const t = pickToken(); if (t) headers.set('Authorization','Bearer '+t);
    let res = await fetchImpl(url,{...opts, headers});
    
    if(res.status===401){
      const rt = localStorage.getItem('app_refresh') || localStorage.getItem('app_refresh_token');
      if(!rt) return res;
      
      // try refresh (r7.9/r8.7 환경: /auth/refresh 또는 /admin/auth/refresh 구분)
      const refreshUrl = '/auth/refresh';
      const rr = await fetchImpl(refreshUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ refresh_token: rt })});
      const j = rr.ok ? await rr.json() : null;
      if(j?.access_token){ localStorage.setItem('app_access', j.access_token); headers.set('Authorization','Bearer '+j.access_token); res = await fetchImpl(url,{...opts, headers}); }
    }
    return res;
  }
  return { fetch: call };
}

// Ad validation panel (maps to /ads/validate & /ads/autofix)
export function mountValidatePanel({ mount, validateUrl='/ads/validate', autofixUrl='/ads/autofix' }){
  const api = withAuth();
  const root = typeof mount==='string' ? document.querySelector(mount) : mount;
  
  root.innerHTML = `
    <div class="card">
      <h3 style="margin:0 0 8px">검토 결과</h3>
      <div id="violations"></div>
      <div class="spacer"></div>
      <button class="btn btn-primary" id="btn-fix">위반사항 자동 수정</button>
      <p class="helper" id="hint"></p>
    </div>`;
  
  const $viol = root.querySelector('#violations');
  const $hint = root.querySelector('#hint');
  const $fix  = root.querySelector('#btn-fix');
  
  async function runValidate(payload){
    $viol.innerHTML = '<span class="helper">검증 중…</span>';
    const r = await api.fetch(validateUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
    const j = await r.json();
    if(!j.ok) {
      $viol.innerHTML = '<span class="pill" style="background:#FEE2E2;color:#991B1B">검증 오류</span>';
      $hint.textContent = j.code || '알 수 없는 오류';
      return j;
    }
    const issues = j.issues || j.violations || [];
    const status = j.valid ? 'GREEN' : (j.summary?.errors > 0 ? 'RED' : 'YELLOW');
    $viol.innerHTML = issues.length ? issues.map(it=>`<span class="pill" role="status" style="${it.severity==='error'?'background:#FEE2E2;color:#991B1B':it.severity==='warn'?'background:#FEF3C7;color:#92400E':'background:#F1F5F9;color:#475569'}">${it.type||it.code}: ${it.message}</span>`).join('') : '<span class="pill" style="background:#ECFDF5;color:#065F46">통과(GREEN)</span>';
    $hint.textContent = j.summary ? `총 ${j.summary.total_issues}건 (에러 ${j.summary.errors}건, 경고 ${j.summary.warnings}건)` : (j.autoFixableCount>0 ? `자동수정 가능 항목 ${j.autoFixableCount}건` : '수정 필요 없음');
    return { ...j, status };
  }
  
  $fix.addEventListener('click', async ()=>{
    const data = window.__adDraft || {}; // 페이지에서 전역으로 제공
    const r = await api.fetch(autofixUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    const j = await r.json();
    if(!j.ok) {
      toast('자동 수정 실패: ' + (j.code || '알 수 없는 오류'), 'error');
      return;
    }
    if(j?.patched || j?.fixed_text){ 
      toast('자동 수정 완료'); 
      // 수정된 텍스트로 업데이트
      if(j.fixed_text && window.__adDraft) window.__adDraft.text = j.fixed_text;
      await runValidate(j.result || { ...data, text: j.fixed_text || data.text }); 
    }
    else toast('수정할 항목이 없습니다','info');
  });
  
  return { validate: runValidate };
}

