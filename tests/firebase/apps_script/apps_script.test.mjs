// Ujian automasi Google Apps Script (apps_script/Code.gs) terhadap emulator:
// emel automatik ibu bapa (EmailJS) + backup harian ke Google Drive.
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { assertSucceeds } from '@firebase/rules-unit-testing';
import {
  Bytes,
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { get, ref, set } from 'firebase/database';
import {
  PROJECT_ID,
  USERS,
  completeProfile,
  createEnv,
  ctx,
  participantPayload,
  seed,
  seedRtdb,
} from '../rules/helpers.mjs';
import { ROOT, loadScript, plain, post } from './gas_runtime.mjs';

const KEY = 'fixture-secret-key'; // nilai ujian sahaja
const WEB_APP_URL = 'https://script.google.com/macros/s/AKfycbTestDeployment_123/exec';
const parity = JSON.parse(readFileSync(resolve(ROOT, 'test/fixtures/email_parity.json'), 'utf8'));

let env;
before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearDatabase();
});

const minutesAgo = (m) => Timestamp.fromMillis(Date.now() - m * 60000);
const script = (config) => loadScript({ projectId: PROJECT_ID, config });

async function seedJoins(joins, { key = KEY, adminOnline = false, extra } = {}) {
  await seed(env, {
    extra: async (db) => {
      for (const j of joins) {
        const pid = j.pid ?? 'p1';
        await setDoc(doc(db, `programs/${pid}/participants/${j.user.uid}`), participantPayload(j.user, pid, {
          joinedAt: j.joinedAt ?? minutesAgo(10),
          emailUpdatedAt: minutesAgo(10),
          ...j.overrides,
        }));
      }
      if (extra) await extra(db);
    },
  });
  await seedRtdb(env, async (db) => {
    await set(ref(db, 'admins/admin1'), true);
    if (key) {
      await set(ref(db, 'admin_workspace/settings/emailjs'), {
        privateKey: key, updatedBy: 'admin1', updatedAt: Date.now(),
      });
    }
    if (adminOnline) {
      await set(ref(db, 'admin_workspace/presence/admin1'), {
        online: true, lastSeen: Date.now(), email: USERS.admin.email, name: 'Staff Admin',
      });
    }
  });
}

async function readDoc(path) {
  let data = null;
  await env.withSecurityRulesDisabled(async (c) => {
    const snap = await getDoc(doc(c.firestore(), path));
    data = snap.exists() ? snap.data() : null;
  });
  return data;
}

async function emailLogs() {
  let out = [];
  await env.withSecurityRulesDisabled(async (c) => {
    const snap = await getDocs(collection(c.firestore(), 'email_logs'));
    out = snap.docs.map((d) => ({ docId: d.id, ...d.data() }));
  });
  return out;
}

async function readRtdb(path) {
  let value = null;
  await env.withSecurityRulesDisabled(async (c) => {
    value = (await get(ref(c.database(), path))).val();
  });
  return value;
}

function queuedLog(id, overrides = {}) {
  return {
    id,
    recipient: 'parent@example.com',
    subject: 'MyParentCare: Maklumat Career Day dikemas kini',
    body: 'Salam sejahtera,\n\nMaklumat program telah dikemas kini.',
    status: 'queued',
    errorMessage: '',
    studentName: 'Nur Aina',
    studentUid: 'alice',
    programId: 'p1',
    programTitle: 'Career Day',
    type: 'update',
    createdBy: 'admin1',
    createdAt: minutesAgo(10),
    updatedAt: minutesAgo(10),
    attempts: 0,
    ...overrides,
  };
}

// ================================================================ emel

describe('Apps Script: emel ibu bapa automatik (EmailJS)', () => {
  it('menghantar emel pengesahan yang SAMA seperti aplikasi, tanpa aplikasi admin dibuka', async () => {
    await seedJoins([{ user: USERS.alice }]);
    const { gas, state } = script();

    const result = plain(gas.processEmails());
    assert.deepEqual(result, { sent: 1, failed: 0, waiting: 0 });

    // Payload EmailJS = fixture yang dijana oleh aplikasi (templat + ID + private key).
    assert.equal(state.emails.length, 1);
    const expected = structuredClone(parity.cases[0].payload);
    expected.accessToken = KEY;
    assert.deepEqual(state.emails[0], expected);

    const participant = await readDoc('programs/p1/participants/alice');
    assert.equal(participant.emailStatus, 'sent');
    assert.ok(participant.emailUpdatedAt.toMillis() > Date.now() - 60000);

    const [log] = await emailLogs();
    assert.equal(log.id, log.docId);
    assert.equal(log.status, 'sent');
    assert.equal(log.type, 'join');
    assert.equal(log.recipient, 'parent@example.com');
    assert.equal(log.studentUid, 'alice');
    assert.equal(log.programId, 'p1');
    assert.equal(log.createdBy, 'apps-script');
    assert.equal(log.attempts, 1);
    assert.ok(log.createdAt instanceof Timestamp);
    assert.equal(log.subject, expected.template_params.subject);
    assert.equal(log.body, expected.template_params.message);
  });

  it('log yang ditulis skrip lulus Security Rules: admin boleh cuba semula, pelajar boleh lihat', async () => {
    await seedJoins([{ user: USERS.alice }]);
    script().gas.processEmails();
    const [log] = await emailLogs();

    const adminDb = ctx(env, USERS.admin).firestore();
    await assertSucceeds(updateDoc(doc(adminDb, `email_logs/${log.docId}`), {
      status: 'sent', errorMessage: '', attempts: 2, updatedAt: serverTimestamp(),
    }));
    const aliceDb = ctx(env, USERS.alice).firestore();
    await assertSucceeds(getDocs(query(collection(aliceDb, 'email_logs'), where('studentUid', '==', 'alice'))));
    // Pelajar masih boleh mengemas kini status emel penyertaan sendiri (medan tidak berubah).
    await assertSucceeds(updateDoc(doc(aliceDb, 'programs/p1/participants/alice'), {
      emailStatus: 'pending', emailUpdatedAt: serverTimestamp(),
    }));
  });

  it('tidak menghantar dua kali: larian kedua tiada emel baharu', async () => {
    await seedJoins([{ user: USERS.alice }, { user: USERS.bob }]);
    const { gas, state } = script();
    assert.equal(plain(gas.processEmails()).sent, 2);
    assert.deepEqual(plain(gas.processEmails()), { sent: 0, failed: 0, waiting: 0 });
    assert.equal(state.emails.length, 2);
    assert.equal((await emailLogs()).length, 2);
    // Had kadar EmailJS: jeda ~1.1 saat antara emel.
    assert.equal(state.sleeps.length, 1);
    assert.ok(state.sleeps[0] > 500 && state.sleeps[0] <= 1100, `jeda ${state.sleeps[0]}`);
  });

  it('butiran program terkini diambil daripada dokumen program; jika dipadam guna salinan peserta', async () => {
    await seedJoins([
      { user: USERS.alice },
      { user: USERS.bob, pid: 'gone', overrides: { programTitle: 'Program Lama', programLocation: 'Bilik 7' } },
    ], {
      extra: (db) => updateDoc(doc(db, 'programs/p1'), { location: 'Dewan Baharu' }),
    });
    const { gas, state } = script();
    gas.processEmails();
    const byTo = Object.fromEntries(state.emails.map((e) => [e.template_params.program_title, e.template_params]));
    assert.equal(byTo['Career Day'].program_location, 'Dewan Baharu');
    assert.equal(byTo['Program Lama'].program_location, 'Bilik 7');
  });

  it('admin sedang dalam talian: penyertaan baharu diberi kepada aplikasi admin, yang lama dihantar skrip', async () => {
    await seedJoins([
      { user: USERS.alice, joinedAt: Timestamp.now() },
      { user: USERS.bob, joinedAt: minutesAgo(10) },
    ], { adminOnline: true });
    const { gas, state } = script();
    assert.deepEqual(plain(gas.processEmails()), { sent: 1, failed: 0, waiting: 1 });
    assert.equal(state.emails[0].template_params.to_email, 'parent@example.com');
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'pending');
    assert.equal((await readDoc('programs/p1/participants/bob')).emailStatus, 'sent');
  });

  it('tiada private key: tiada emel dihantar, emel kekal menunggu, amaran sekali sahaja', async () => {
    await seedJoins([{ user: USERS.alice }], { key: null });
    const { gas, state } = script();
    assert.equal(plain(gas.processEmails()).waiting, 1);
    gas.processEmails();
    assert.equal(state.emails.length, 0);
    assert.equal(state.mails.length, 1);
    assert.match(state.mails[0].subject, /Private key EmailJS tiada/);
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'pending');
  });

  it('EmailJS 403/426 (masalah akaun): berhenti, emel kekal pending, amaran tanpa mendedahkan kunci', async () => {
    await seedJoins([{ user: USERS.alice }, { user: USERS.bob }]);
    const { gas, state } = script();
    state.emailResponder = () => ({ code: 403, text: 'API access in strict mode, but no Private Key was provided' });
    assert.equal(plain(gas.processEmails()).waiting, 1);
    assert.equal(state.emails.length, 1, 'berhenti selepas ralat pertama');
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'pending');
    assert.equal((await readDoc('programs/p1/participants/bob')).emailStatus, 'pending');
    assert.equal((await emailLogs()).length, 0);
    assert.equal(state.mails.length, 1);
    assert.match(state.mails[0].body, /strict mode/);
    assert.ok(!state.mails[0].body.includes(KEY));

    // Selepas masalah diselesaikan, emel dihantar secara automatik.
    state.emailResponder = () => ({ code: 200, text: 'OK' });
    assert.equal(plain(gas.processEmails()).sent, 2);
  });

  it('EmailJS 400 (emel tertentu ditolak): ditanda failed dengan mesej yang sama seperti aplikasi', async () => {
    await seedJoins([{ user: USERS.alice }]);
    const { gas, state } = script();
    state.emailResponder = () => ({ code: 400, text: 'The template ID is invalid' });
    assert.equal(plain(gas.processEmails()).failed, 1);
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'failed');
    const [log] = await emailLogs();
    assert.equal(log.status, 'failed');
    assert.equal(log.errorMessage, parity.errors[0].message);
  });

  it('emel dalam barisan (kemas kini/pembatalan) dihantar dan log dikemas kini', async () => {
    await seedJoins([{ user: USERS.alice, overrides: { emailStatus: 'sent' } }], {
      extra: async (db) => {
        await setDoc(doc(db, 'email_logs/q1'), queuedLog('q1'));
        await setDoc(doc(db, 'email_logs/q2'), queuedLog('q2', { type: 'join', subject: 'Join', body: 'Join body' }));
        await setDoc(doc(db, 'email_logs/done'), queuedLog('done', { status: 'sent', attempts: 1 }));
      },
    });
    await env.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), 'programs/p1/participants/alice'), { emailStatus: 'failed' }));
    const { gas, state } = script();
    assert.deepEqual(plain(gas.processEmails()), { sent: 2, failed: 0, waiting: 0 });
    const first = state.emails.find((e) => e.template_params.subject === queuedLog('q1').subject);
    assert.deepEqual(first.template_params, {
      to_email: 'parent@example.com',
      subject: queuedLog('q1').subject,
      message: queuedLog('q1').body,
      student_name: 'Nur Aina',
      program_title: 'Career Day',
      program_date: '',
      program_time: '',
      program_location: '',
      reason: '',
      type: 'update',
    });
    const q1 = await readDoc('email_logs/q1');
    assert.equal(q1.status, 'sent');
    assert.equal(q1.attempts, 1);
    assert.ok(q1.updatedAt.toMillis() > q1.createdAt.toMillis());
    // Log jenis join turut mengemas kini status peserta (seperti aplikasi).
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'sent');
    assert.equal(plain(gas.processEmails()).sent, 0);
  });

  it('larian bertindih disekat oleh kunci skrip', async () => {
    await seedJoins([{ user: USERS.alice }]);
    const { gas, state } = script();
    state.lockBusy = true;
    assert.deepEqual(plain(gas.processEmails()), { busy: true });
    assert.equal(state.emails.length, 0);
  });

  it('ralat EmailJS diterjemah sama seperti aplikasi (describeError)', () => {
    const { gas } = script();
    for (const e of parity.errors) {
      assert.equal(gas.describeEmailJsError_(e.status, e.body), e.message, `HTTP ${e.status}`);
    }
  });

  it('templat pengesahan sama dengan aplikasi untuk semua kes fixture', () => {
    const { gas } = script();
    for (const c of parity.cases) {
      const message = gas.joinMessage_(c.input.parentEmail, c.input.studentName, c.input.program);
      assert.deepEqual(plain(gas.emailJsPayload_(message, 'fixture-private-key')), c.payload);
    }
  });
});

// ====================================================== emel segera

describe('Apps Script: emel SEGERA selepas pelajar join (web app)', () => {
  it('panggilan dari aplikasi pelajar terus menghantar emel yang sama seperti aplikasi', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }], { adminOnline: true });
    const { gas, state } = script();
    const started = Date.now();
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'sent' });
    assert.ok(Date.now() - started < 5000);

    const expected = structuredClone(parity.cases[0].payload);
    expected.accessToken = KEY;
    assert.deepEqual(state.emails, [expected]);
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'sent');
    const [log] = await emailLogs();
    assert.equal(log.status, 'sent');
    assert.equal(log.createdBy, 'apps-script');

    // Trigger 5 minit & panggilan berulang tidak menghantar lagi.
    assert.equal(plain(gas.processEmails()).sent, 0);
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'sent' });
    assert.equal(state.emails.length, 1);
    assert.equal((await emailLogs()).length, 1);
  });

  it('tidak boleh disalah guna: ID tidak sah, penyertaan tiada, atau emel sudah dihantar → tiada emel', async () => {
    await seedJoins([{ user: USERS.bob, overrides: { emailStatus: 'sent' } }]);
    const { gas, state } = script();
    for (const body of [
      { action: 'join', programId: 'p1/../users', uid: 'alice' },
      { action: 'join', programId: 'p1', uid: '' },
      { action: 'join', programId: 'p1', uid: 'a'.repeat(200) },
      { action: 'send', to: 'victim@example.com', message: 'spam' },
      {},
    ]) {
      assert.deepEqual(post(gas, body), { ok: false, status: 'invalid' }, JSON.stringify(body));
    }
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: false, status: 'not_found' });
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'bob' }), { ok: true, status: 'sent' });
    // Badan bukan JSON juga ditolak dengan selamat.
    const raw = gas.doPost({ postData: { contents: 'not json' } });
    assert.deepEqual(JSON.parse(raw.getContent()), { ok: false, status: 'invalid' });
    assert.equal(state.emails.length, 0);
  });

  it('jika laluan lain sedang menghantar penyertaan sama → "queued", tiada emel berganda', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }]);
    const { gas, state } = script();
    const name = `projects/${PROJECT_ID}/databases/(default)/documents/programs/p1/participants/alice`;
    state.cache.set(`p:${name}`, { value: '1', expires: Date.now() + 60000 });
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'queued' });
    assert.equal(plain(gas.processEmails()).sent, 0);
    assert.equal(state.emails.length, 0);
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'pending');
  });

  it('EmailJS menolak (403) → kekal pending & tuntutan dilepaskan supaya trigger boleh cuba semula', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }]);
    const { gas, state } = script();
    state.emailResponder = () => ({ code: 403, text: 'API access in strict mode, but no Private Key was provided' });
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'queued' });
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'pending');
    assert.equal(state.mails.length, 1);

    state.emailResponder = () => ({ code: 200, text: 'OK' });
    assert.equal(plain(gas.processEmails()).sent, 1);
    assert.equal((await readDoc('programs/p1/participants/alice')).emailStatus, 'sent');
  });

  it('tiada private key → queued (tiada emel), pemilik dimaklumkan', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }], { key: null });
    const { gas, state } = script();
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'queued' });
    assert.equal(state.emails.length, 0);
    assert.match(state.mails[0].subject, /Private key EmailJS tiada/);
  });

  it('ramai pelajar serentak: had kadar EmailJS dikongsi; giliran terlalu panjang diserah kepada trigger', async () => {
    await seedJoins([
      { user: USERS.alice, joinedAt: Timestamp.now() },
      { user: USERS.bob, joinedAt: Timestamp.now() },
    ]);
    const { gas, state } = script({ maxInstantWaitMs: 500 });
    assert.equal(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }).status, 'sent');
    // Slot EmailJS seterusnya ~1.1 s lagi (> 500 ms) → bob diserah kepada trigger.
    assert.equal(post(gas, { action: 'join', programId: 'p1', uid: 'bob' }).status, 'queued');
    assert.equal((await readDoc('programs/p1/participants/bob')).emailStatus, 'pending');
    assert.equal(plain(gas.processEmails()).sent, 1);
    assert.equal((await readDoc('programs/p1/participants/bob')).emailStatus, 'sent');
    assert.equal(state.emails.length, 2);
  });

  it('had permintaan seminit melindungi kuota Firestore', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }]);
    const { gas, state } = script({ maxRequestsPerMinute: 2 });
    post(gas, { action: 'join', programId: 'p1', uid: 'bob' });
    post(gas, { action: 'join', programId: 'p1', uid: 'bob' });
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'queued' });
    assert.equal(state.emails.length, 0);
  });

  it('ping (GET) & setup menyimpan pautan web app ke public/config yang boleh dibaca pelajar', async () => {
    await seedJoins([]);
    const { gas, state } = script();
    assert.deepEqual(JSON.parse(gas.doGet().getContent()), {
      ok: true, service: 'myparentcare-email', version: 2, keyConfigured: true, triggers: [],
    });

    state.webAppUrl = 'https://script.google.com/macros/s/AKfycbTestDeployment_123/dev';
    let lines = plain(gas.setup());
    assert.match(lines.join('\n'), /Emel segera \(web app\): BELUM/);
    assert.equal(await readDoc('public/config'), null);

    state.webAppUrl = WEB_APP_URL;
    lines = plain(gas.setup());
    assert.deepEqual(JSON.parse(gas.doGet().getContent()).triggers, ['dailyBackup', 'processEmails']);
    assert.match(lines.join('\n'), /Emel segera \(web app\): OK/);
    const config = await readDoc('public/config');
    assert.equal(config.emailRelayUrl, WEB_APP_URL);
    assert.equal(config.emailRelayUpdatedBy, 'apps-script');
    assert.ok(config.emailRelayUpdatedAt instanceof Timestamp);

    const aliceDb = ctx(env, USERS.alice).firestore();
    await assertSucceeds(getDoc(doc(aliceDb, 'public/config')));

    state.webAppDown = true;
    assert.match(plain(gas.checkSetup()).join('\n'), /Emel segera \(web app\): GAGAL/);
  });
});

// ============================================ kegagalan: sandaran & notifikasi

async function notificationsOf(uid) {
  let out = [];
  await env.withSecurityRulesDisabled(async (c) => {
    const snap = await getDocs(collection(c.firestore(), `users/${uid}/notifications`));
    out = snap.docs.map((d) => ({ docId: d.id, ...d.data() }));
  });
  return out;
}

describe('Apps Script: bila emel gagal – admin nampak sebab, pelajar dimaklumkan', () => {
  it('emel ditolak (400): status failed + sebab dalam log admin + notifikasi pelajar SEKALI', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }]);
    const { gas, state } = script();
    state.emailResponder = () => ({ code: 400, text: 'The recipients address is corrupted' });
    assert.deepEqual(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }), { ok: true, status: 'failed' });

    const [log] = await emailLogs();
    assert.equal(log.status, 'failed');
    assert.match(log.errorMessage, /EmailJS menolak permintaan/);

    const notes = await notificationsOf('alice');
    assert.equal(notes.length, 1);
    assert.equal(notes[0].type, 'info');
    assert.equal(notes[0].title, 'Emel kepada ibu bapa gagal dihantar');
    assert.match(notes[0].message, /Career Day/);
    assert.match(notes[0].message, /parent@example\.com/);
    assert.match(notes[0].message, /Alamat emel ibu bapa mungkin tidak sah/);
    assert.equal(notes[0].id, notes[0].docId);
    assert.equal(notes[0].isRead, false);
    assert.ok(notes[0].createdAt instanceof Timestamp);
    assert.equal((await readDoc('users/alice')).unreadNotifications, 1);

    // Pelajar boleh membaca & menandakan notifikasi dibaca (Security Rules).
    const aliceDb = ctx(env, USERS.alice).firestore();
    await assertSucceeds(getDocs(collection(aliceDb, 'users/alice/notifications')));
    await assertSucceeds(updateDoc(doc(aliceDb, `users/alice/notifications/${notes[0].docId}`), { isRead: true }));

    // Admin cuba semula (masih gagal): tiada notifikasi berganda.
    await env.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), 'programs/p1/participants/alice'), { emailStatus: 'pending' }));
    script().gas.processEmails();
    assert.equal((await notificationsOf('alice')).length, 1);
    assert.equal((await readDoc('users/alice')).unreadNotifications, 1);
  });

  it('masalah akaun EmailJS (426): emel kekal pending, pelajar dimaklumkan "tertangguh", admin nampak sebab', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }, { user: USERS.bob }]);
    const { gas, state } = script();
    state.emailResponder = () => ({ code: 426, text: 'Account quota exceeded' });
    assert.equal(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }).status, 'queued');
    gas.processEmails();

    for (const uid of ['alice', 'bob']) {
      assert.equal((await readDoc(`programs/p1/participants/${uid}`)).emailStatus, 'pending');
      const notes = await notificationsOf(uid);
      assert.equal(notes.length, 1, uid);
      assert.equal(notes[0].title, 'Emel kepada ibu bapa tertangguh');
      assert.match(notes[0].message, /mencuba semula secara automatik/);
    }
    const status = await readRtdb('admin_workspace/automation/email');
    assert.equal(status.ok, false);
    assert.equal(status.code, '426');
    assert.match(status.message, /Kuota EmailJS telah habis/);
    assert.ok(status.at > Date.now() - 60000);
    assert.equal(state.mails.length, 1, 'pemilik menerima satu emel amaran');

    // Larian seterusnya: tiada notifikasi berulang.
    gas.processEmails();
    assert.equal((await notificationsOf('alice')).length, 1);

    // Masalah selesai → emel dihantar, status admin kembali OK.
    state.emailResponder = () => ({ code: 200, text: 'OK' });
    assert.equal(plain(gas.processEmails()).sent, 2);
    assert.equal((await readRtdb('admin_workspace/automation/email')).ok, true);
  });

  it('ralat sementara (429) pada penyertaan baharu: tiada notifikasi pelajar lagi (dicuba semula)', async () => {
    await seedJoins([{ user: USERS.alice, joinedAt: Timestamp.now() }]);
    const { gas, state } = script();
    state.emailResponder = () => ({ code: 429, text: 'Too many requests' });
    assert.equal(post(gas, { action: 'join', programId: 'p1', uid: 'alice' }).status, 'queued');
    assert.equal((await notificationsOf('alice')).length, 0);
    assert.equal(state.mails.length, 0, '429 bukan amaran kepada pemilik');
  });

  it('private key tiada: status admin menunjukkan sebab, pelajar dimaklumkan tertangguh', async () => {
    await seedJoins([{ user: USERS.alice }], { key: null });
    const { gas } = script();
    gas.processEmails();
    const status = await readRtdb('admin_workspace/automation/email');
    assert.equal(status.ok, false);
    assert.equal(status.code, 'key');
    assert.match(status.message, /Email settings/);
    assert.equal((await notificationsOf('alice'))[0].title, 'Emel kepada ibu bapa tertangguh');
  });

  it('admin boleh membaca status automasi (RTDB rules), pelajar tidak', async () => {
    await seedJoins([{ user: USERS.alice }], { key: null });
    script().gas.processEmails();
    const { assertFails } = await import('@firebase/rules-unit-testing');
    await assertSucceeds(get(ref(ctx(env, USERS.admin).database(), 'admin_workspace/automation/email')));
    await assertFails(get(ref(ctx(env, USERS.alice).database(), 'admin_workspace/automation/email')));
    await assertFails(set(ref(ctx(env, USERS.admin).database(), 'admin_workspace/automation/email'), { ok: true }));
  });
});

// ============================================================== backup

async function seedForBackup() {
  await seed(env, {
    extra: async (db) => {
      await setDoc(doc(db, 'programs/p1/participants/alice'), participantPayload(USERS.alice, 'p1', {
        joinedAt: minutesAgo(30), emailUpdatedAt: minutesAgo(29), emailStatus: 'sent',
      }));
      await setDoc(doc(db, 'programs/p1/participants/bob'), participantPayload(USERS.bob, 'p1', {
        joinedAt: minutesAgo(20), emailUpdatedAt: minutesAgo(20),
      }));
      await setDoc(doc(db, 'users/alice/notifications/n1'), {
        id: 'n1', title: 'Selamat datang', body: 'Hai', read: false, createdAt: minutesAgo(5),
      });
      await setDoc(doc(db, 'media/m1'), {
        id: 'm1', programId: 'p1', kind: 'image', mimeType: 'image/png',
        bytes: Bytes.fromUint8Array(new Uint8Array([137, 80, 78, 71, 1, 2, 3])),
        createdAt: minutesAgo(40), createdBy: 'admin1',
      });
      await setDoc(doc(db, 'email_logs/l1'), queuedLog('l1', { status: 'sent', type: 'join', attempts: 1 }));
      await setDoc(doc(db, 'account_deletions/d1'), { uid: 'gone', reason: 'test', deletedAt: minutesAgo(60) });
    },
  });
  await seedRtdb(env, async (db) => {
    await set(ref(db, 'admins/admin1'), true);
    await set(ref(db, 'admin_workspace/settings/emailjs'), { privateKey: KEY, updatedBy: 'admin1', updatedAt: 1 });
    await set(ref(db, 'admin_workspace/notes/n1'), { text: 'Nota admin', by: 'admin1', at: 1 });
    await set(ref(db, 'admin_workspace/audit_logs/a1'), { action: 'program.create', actorUid: 'admin1', at: 1 });
    await set(ref(db, 'users/legacy1'), { email: 'old@kptm.test', fullName: 'Pelajar Lama' });
  });
}

const EXPECTED_COUNTS = {
  users: 4, programs: 2, program_seats: 3, participants: 2, notifications: 1,
  public: 1, media: 1, email_logs: 1, account_deletions: 1,
};

describe('Apps Script: backup harian ke Google Drive', () => {
  it('backup penuh dalam format aplikasi, tanpa private key, direkod untuk papan pemuka admin', async () => {
    await seedForBackup();
    const { gas, state } = script();
    const result = plain(gas.dailyBackup());
    assert.equal(result.error, undefined, result.error);
    assert.equal(result.documents, 16);
    assert.deepEqual(result.skipped, []);

    const [folder] = state.folders;
    assert.equal(folder.name, 'MyParentCare Backups');
    assert.equal(folder.files.length, 1);
    const file = folder.files[0];
    assert.match(file.name, /^myparentcare_backup_\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d\.json$/);
    assert.equal(file.mimeType, 'application/json');
    assert.ok(!file.content.includes(KEY), 'private key tidak boleh masuk backup');

    const backup = JSON.parse(file.content);
    assert.equal(backup.format, 'myparentcare-backup');
    assert.equal(backup.version, 1);
    assert.equal(backup.createdBy, 'owner@kptm.test (automatik)');
    assert.deepEqual(backup.counts, EXPECTED_COUNTS);
    assert.deepEqual(Object.keys(backup.firestore), Object.keys(EXPECTED_COUNTS));
    assert.equal(backup.firestore.participants.p1.alice.joinedAt.__type, 'timestamp');
    assert.ok(!Number.isNaN(Date.parse(backup.firestore.participants.p1.alice.joinedAt.value)));
    assert.deepEqual(backup.firestore.media.m1.bytes, {
      __type: 'bytes', value: Buffer.from([137, 80, 78, 71, 1, 2, 3]).toString('base64'),
    });
    assert.equal(backup.firestore.program_seats.p1.s0.cap, 1);
    assert.equal(backup.firestore.notifications.alice.n1.title, 'Selamat datang');
    assert.equal(backup.firestore.users.alice.fullName, completeProfile(USERS.alice).fullName);
    assert.equal(backup.rtdb.admins.admin1, true);
    assert.equal(backup.rtdb.admin_workspace.settings, undefined);
    assert.equal(backup.rtdb.admin_workspace.notes.n1.text, 'Nota admin');
    assert.equal(backup.rtdbOther.users.legacy1.fullName, 'Pelajar Lama');

    const records = Object.values(await readRtdb('admin_workspace/backups'));
    assert.equal(records.length, 1);
    assert.equal(records[0].kind, 'backup');
    assert.equal(records[0].by, 'apps-script');
    assert.equal(records[0].byEmail, 'owner@kptm.test');
    assert.equal(records[0].documents, 16);
    assert.ok(records[0].at > Date.now() - 60000);
    assert.match(records[0].note, /MyParentCare Backups/);

    if (process.env.UPDATE_FIXTURES === '1') {
      writeFileSync(resolve(ROOT, 'test/fixtures/apps_script_backup.json'), file.content);
    }
  });

  it('had bacaan Spark: data besar → log dilangkau dahulu dan pemilik dimaklumkan', async () => {
    await seedForBackup();
    const { gas, state } = script({ backupReadBudget: 15 });
    const result = plain(gas.dailyBackup());
    assert.deepEqual(result.skipped, ['notifications']);
    assert.equal(result.documents, 15);
    const backup = JSON.parse(state.folders[0].files[0].content);
    assert.equal(backup.firestore.notifications, undefined);
    assert.deepEqual(backup.skipped, ['notifications']);
    assert.equal(state.mails.length, 1);

    const tight = script({ backupReadBudget: 14 });
    assert.deepEqual(plain(tight.gas.dailyBackup()).skipped, ['notifications', 'email_logs']);
  });

  it('backup besar: media disimpan dalam fail berasingan (had 50 MB setiap fail)', async () => {
    await seedForBackup();
    const { gas, state } = script({ maxFileChars: 500 });
    const result = plain(gas.dailyBackup());
    assert.equal(result.files.length, 2);
    assert.equal(result.documents, 16);
    const files = state.folders[0].files;
    const main = JSON.parse(files.find((f) => !f.name.endsWith('_media.json')).content);
    const media = JSON.parse(files.find((f) => f.name.endsWith('_media.json')).content);
    assert.equal(main.firestore.media, undefined);
    assert.equal(main.mediaFile, files.find((f) => f.name.endsWith('_media.json')).name);
    assert.equal(media.format, 'myparentcare-backup');
    assert.deepEqual(media.counts, { media: 1 });
    assert.ok(media.firestore.media.m1.bytes.value);
  });

  it('simpanan: harian 30 hari, Isnin hingga 90 hari, fail manual tidak disentuh', () => {
    const { gas, state } = script();
    const folder = gas.backupFolder_();
    const DAY = 86400000;
    const shift = (days, monday) => {
      let t = Date.now() - days * DAY;
      while ((new Date(t + 8 * 3600000).getUTCDay() === 1) !== monday) t -= DAY;
      return t;
    };
    const add = (name, created, auto = true) => {
      const f = folder.createFile(name, '{}', 'application/json');
      if (auto) f.setDescription('MyParentCare backup automatik (Apps Script)');
      f.created = new Date(created);
      return f;
    };
    const recent = add('recent', Date.now() - 10 * DAY);
    const weekly = add('weekly', shift(40, true));
    const daily = add('daily-old', shift(40, false));
    const ancient = add('ancient-monday', shift(100, true));
    const manual = add('manual', Date.now() - 200 * DAY, false);
    assert.equal(gas.pruneBackups_(folder, Date.now()), 2);
    assert.deepEqual(
      [recent, weekly, daily, ancient, manual].map((f) => f.trashed),
      [false, false, true, true, false],
    );
    assert.equal(state.folders.length, 1);
  });

  it('setup() memasang 2 trigger sekali sahaja dan checkSetup melaporkan SEMUA OK', async () => {
    await seedJoins([]);
    const { gas, state } = script();
    state.webAppUrl = WEB_APP_URL;
    gas.setup();
    const lines = plain(gas.setup());
    assert.equal(state.triggers.length, 2);
    const byName = Object.fromEntries(state.triggers.map((t) => [t.getHandlerFunction(), t.schedule]));
    assert.deepEqual(plain(byName.processEmails), { everyMinutes: 5 });
    assert.deepEqual(plain(byName.dailyBackup), { everyDays: 1, atHour: 3 });
    assert.equal(lines.at(-1), 'SEMUA OK', lines.join('\n'));
    assert.ok(!lines.join('\n').includes(KEY));
    gas.removeTriggers();
    assert.equal(state.triggers.length, 0);
  });

  it('checkSetup melaporkan private key yang tiada', async () => {
    await seedJoins([], { key: null });
    const lines = plain(script().gas.checkSetup());
    assert.match(lines.join('\n'), /Private key EmailJS: TIADA/);
    assert.match(lines.at(-1), /ADA MASALAH/);
  });
});
