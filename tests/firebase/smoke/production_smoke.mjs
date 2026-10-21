// Ujian request ke PRODUCTION selepas deploy (tanpa log masuk).
// Mengesahkan data tidak lagi terbuka kepada umum dan halaman web tersedia.
//
//   cd tests/firebase && npm run smoke
//
// Semakan tulis hanya dijalankan dengan --write-check (SELEPAS rules di-deploy).
// Jika tulisan tidak dijangka berjaya, nod ujian terus dipadam semula.

const PROJECT = 'myparentcare-45eb1';
const RTDB = 'https://myparentcare-45eb1-default-rtdb.asia-southeast1.firebasedatabase.app';
const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const WEB = process.env.WEB_URL ?? 'https://website-81b96.web.app';
const OLD_WEB = `https://${PROJECT}.web.app`;
// Web app Google Apps Script (emel segera + trigger 5 minit + backup harian).
const APPS_SCRIPT = process.env.APPS_SCRIPT_URL ??
  'https://script.google.com/macros/s/AKfycbxIfTZ695gA2cOBtSSJ3aqH1hg1TmAwrS9UA-jOcIWJM5dibiEV4AtuTnNSWuvTrVIIhw/exec';

const results = [];
async function check(label, fn) {
  try {
    const detail = await fn();
    results.push([true, label, detail ?? '']);
  } catch (error) {
    results.push([false, label, error.message]);
  }
}

async function expectStatus(url, init, allowed) {
  const res = await fetch(url, init);
  if (!allowed.includes(res.status)) {
    const body = (await res.text()).slice(0, 120);
    throw new Error(`status ${res.status} (dijangka ${allowed.join('/')}) ${body}`);
  }
  return `HTTP ${res.status}`;
}

const denied = [401, 403];

// --- Realtime Database (ruang kerja admin + data lama) ------------------
for (const path of ['', 'users', 'participants', 'email_logs', 'admins', 'admin_workspace']) {
  await check(`RTDB /${path} tidak boleh dibaca tanpa log masuk`, () =>
    expectStatus(`${RTDB}/${path}.json?shallow=true`, {}, denied));
}
if (process.argv.includes('--write-check')) {
  await check('RTDB tidak boleh ditulis tanpa log masuk', async () => {
    const res = await fetch(`${RTDB}/smoke_test.json`, { method: 'PUT', body: '"x"' });
    if (denied.includes(res.status)) return `HTTP ${res.status}`;
    await fetch(`${RTDB}/smoke_test.json`, { method: 'DELETE' }); // bersihkan
    throw new Error(`status ${res.status}: database BOLEH ditulis oleh umum (nod ujian telah dipadam)`);
  });
}

// --- Cloud Firestore ----------------------------------------------------
for (const path of ['public/catalog', 'public/config', 'users', 'programs', 'email_logs', 'media']) {
  await check(`Firestore ${path} tidak boleh dibaca tanpa log masuk`, () =>
    expectStatus(`${FIRESTORE}/${path}`, {}, denied));
}
await check('Firestore: tidak boleh mencipta admin tanpa log masuk', () =>
  expectStatus(`${FIRESTORE}/users?documentId=smoke_admin`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: { role: { stringValue: 'admin' } } }),
  }, denied));

// --- Hosting (web testing + Play Store URLs) -------------------------------
await check('Laman muat turun mengandungi pautan APK Google Drive', async () => {
  const body = await (await fetch(`${WEB}/`)).text();
  const m = body.match(/href="(https:\/\/drive\.google\.com\/file\/d\/[^"]+)"/);
  if (!m) throw new Error('tiada pautan Drive');
  return m[1].split('/')[5];
});
await check('Tiada versi web aplikasi (myparentcare-45eb1 redirect ke laman muat turun)', async () => {
  for (const path of ['/', '/main.dart.js', '/privacy']) {
    const res = await fetch(`${OLD_WEB}${path}`, { redirect: 'manual' });
    const to = res.headers.get('location') ?? '';
    if (res.status !== 301 || !to.startsWith(WEB)) throw new Error(`${path}: ${res.status} ${to}`);
  }
  return '301';
});
for (const [path, text] of [
  ['/', 'Muat turun untuk Android'],
  ['/privacy', 'Dasar Privasi'],
  ['/delete-account', 'Padam Akaun'],
]) {
  await check(`Web ${path} tersedia`, async () => {
    const res = await fetch(`${WEB}${path}`);
    const body = await res.text();
    if (res.status !== 200) throw new Error(`status ${res.status}`);
    if (!body.includes(text)) throw new Error(`tiada teks "${text}"`);
    return 'HTTP 200';
  });
}
await check('Web: header keselamatan (X-Frame-Options, nosniff)', async () => {
  const res = await fetch(`${WEB}/privacy`);
  const frame = res.headers.get('x-frame-options');
  const sniff = res.headers.get('x-content-type-options');
  if (frame !== 'DENY' || sniff !== 'nosniff') throw new Error(`${frame} / ${sniff}`);
  return 'OK';
});

// --- Automasi Apps Script (baca sahaja; tiada emel dihantar) --------------
/** POST seperti aplikasi pelajar: Apps Script menjawab 302 → GET hasilnya. */
async function postAppsScript(body) {
  const first = await fetch(APPS_SCRIPT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    redirect: 'manual',
  });
  const location = first.headers.get('location');
  const res = location ? await fetch(location) : first;
  return res.json();
}

await check('Apps Script: web app aktif, private key ada, trigger dipasang', async () => {
  const pong = await (await fetch(APPS_SCRIPT)).json();
  if (pong.service !== 'myparentcare-email' || pong.ok !== true) throw new Error(JSON.stringify(pong));
  if (pong.keyConfigured !== true) throw new Error('private key EmailJS TIADA');
  const triggers = [...(pong.triggers ?? [])].sort().join(',');
  if (triggers !== 'dailyBackup,processEmails') throw new Error(`trigger: ${triggers || 'tiada'}`);
  return `v${pong.version}, trigger ${triggers}`;
});
await check('Apps Script: permintaan tidak sah ditolak (tidak boleh dijadikan spam relay)', async () => {
  const res = await postAppsScript({ action: 'send', to: 'victim@example.com', message: 'spam' });
  if (res.ok !== false || res.status !== 'invalid') throw new Error(JSON.stringify(res));
  const bad = await postAppsScript({ action: 'join', programId: '../users', uid: 'x' });
  if (bad.status !== 'invalid') throw new Error(JSON.stringify(bad));
  return 'invalid';
});
await check('Apps Script: penyertaan yang tiada → not_found (tiada emel)', async () => {
  const res = await postAppsScript({ action: 'join', programId: 'smokeProgram', uid: 'smokeUser' });
  if (res.status !== 'not_found') throw new Error(JSON.stringify(res));
  return 'not_found';
});

let failed = 0;
for (const [ok, label, detail] of results) {
  console.log(`${ok ? '✔' : '✖'} ${label}${detail ? `  (${detail})` : ''}`);
  if (!ok) failed++;
}
console.log(`\n${results.length - failed}/${results.length} semakan lulus`);
process.exit(failed ? 1 : 0);
