// Ujian beban MyParentCare terhadap Firebase Emulator.
//
// Senario (boleh diubah melalui env):
//   USERS=2000     jumlah pelajar berdaftar yang membuka katalog
//   JOINERS=400    pelajar yang menekan "Join" serentak pada satu program
//   CAPACITY=150   kapasiti program
//   DOUBLE_TAP=50  pelajar yang menekan butang dua kali serentak
//
// Jalankan: firebase emulators:exec --project demo-myparentcare \
//   --only firestore,database "cd tests/firebase && npm run load"
//
// Semakan wajib: tiada overbooking, tiada penyertaan berganda, kaunter tempat
// sama dengan bilangan dokumen penyertaan, dan setiap pelajar mendapat jawapan.

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  runTransaction,
  serverTimestamp,
  setDoc,
  writeBatch,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');

const USERS = Number(process.env.USERS ?? 2000);
const JOINERS = Number(process.env.JOINERS ?? 400);
const CAPACITY = Number(process.env.CAPACITY ?? 150);
const DOUBLE_TAP = Number(process.env.DOUBLE_TAP ?? 50);
const READ_CONCURRENCY = Number(process.env.READ_CONCURRENCY ?? 100);
const PID = 'load_program';
// Sama seperti SeatPlanner.shardCaps dalam aplikasi: ~10 tempat setiap shard, maks 50 shard.
const SHARDS = Math.min(50, Math.max(1, Math.ceil(CAPACITY / 10)));
const shardCaps = Array.from({ length: SHARDS }, (_, k) =>
  Math.floor(CAPACITY / SHARDS) + (k < CAPACITY % SHARDS ? 1 : 0));
const shardId = (k) => `s${String(k).padStart(2, '0')}`;

const env = await initializeTestEnvironment({
  projectId: 'demo-myparentcare',
  firestore: { rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8') },
});
await env.clearFirestore();

const uidOf = (i) => `student_${String(i).padStart(4, '0')}`;
const emailOf = (i) => `${uidOf(i)}@student.test`;

function profile(i) {
  return {
    uid: uidOf(i), email: emailOf(i), role: 'student', status: 'active', authProvider: 'google',
    fullName: `Pelajar ${i}`, matricNo: `KPTM${i}`, course: 'Computer Science', semester: '3',
    phone: '0123456789', parentName: `Ibu ${i}`, parentEmail: `parent${i}@example.com`,
    parentPhone: '0198765432', relationship: 'Mother', profileCompletePercent: 100,
    privacyVersion: '2026-09-30', unreadNotifications: 0,
    createdAt: new Date(), updatedAt: new Date(), consentAt: new Date(),
  };
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}

async function pool(items, limit, worker) {
  const results = [];
  let index = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (index < items.length) {
      const current = index++;
      results[current] = await worker(items[current], current);
    }
  });
  await Promise.all(runners);
  return results;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --------------------------------------------------------------- 1. seed data
console.log(`\n▶ Menyediakan ${USERS} pelajar, program kapasiti ${CAPACITY} (${SHARDS} shard)...`);
let t0 = Date.now();
await env.withSecurityRulesDisabled(async (c) => {
  const db = c.firestore();
  for (let start = 0; start < USERS; start += 450) {
    const batch = writeBatch(db);
    for (let i = start; i < Math.min(start + 450, USERS); i++) {
      batch.set(doc(db, `users/${uidOf(i)}`), profile(i));
    }
    await batch.commit();
  }
  await setDoc(doc(db, `programs/${PID}`), {
    id: PID, title: 'Hari Kerjaya 2026', description: 'Ujian beban', date: '2026-12-01',
    time: '09:00', location: 'Dewan Utama', capacity: CAPACITY, category: 'Career',
    status: 'open', cancellationReason: '',
  });
  for (let k = 0; k < SHARDS; k++) {
    await setDoc(doc(db, `program_seats/${PID}/shards/${shardId(k)}`), { count: 0, cap: shardCaps[k] });
  }
  const programs = {};
  for (let i = 0; i < 40; i++) {
    programs[`p${i}`] = {
      id: `p${i}`, title: `Program ${i}`, description: 'x'.repeat(600), date: '2026-12-01',
      time: '09:00', location: 'Dewan', capacity: 100, category: 'Academic', status: 'open',
    };
  }
  await setDoc(doc(db, 'public/catalog'), { programs, announcements: {}, updatedAt: new Date() });
});
console.log(`  siap dalam ${Date.now() - t0} ms`);

// ------------------------------------------- 2. 2000 pelajar membaca katalog
console.log(`\n▶ ${USERS} pelajar membuka aplikasi (baca profil + katalog, ${READ_CONCURRENCY} serentak)...`);
t0 = Date.now();
const readLatencies = [];
let readErrors = 0;
await pool([...Array(USERS).keys()], READ_CONCURRENCY, async (i) => {
  const c = env.authenticatedContext(uidOf(i), { email: emailOf(i), email_verified: true });
  const db = c.firestore();
  const start = Date.now();
  try {
    await getDoc(doc(db, `users/${uidOf(i)}`));
    await getDoc(doc(db, 'public/catalog'));
    readLatencies.push(Date.now() - start);
  } catch (e) {
    readErrors++;
  } finally {
    await db.app.delete().catch(() => {});
  }
});
const readSeconds = (Date.now() - t0) / 1000;
console.log(`  ${USERS * 2} bacaan dalam ${readSeconds.toFixed(1)} s ` +
  `(≈${Math.round((USERS * 2) / readSeconds)} bacaan/s), p50=${percentile(readLatencies, 50)} ms, ` +
  `p95=${percentile(readLatencies, 95)} ms, ralat=${readErrors}`);

// ----------------------------------- 3. pelajar menekan Join serentak (spike)
// Satu query (≈SHARDS bacaan) untuk mengetahui shard mana yang sudah penuh.
async function refreshFullShards(db, knownFull) {
  const shards = await getDocs(collection(db, `program_seats/${PID}/shards`));
  shards.forEach((s) => {
    if (s.data().count >= s.data().cap) knownFull.add(s.id);
  });
}

async function joinWithRetry(db, i) {
  // Logik sama seperti ProgramRepository.joinProgram dalam aplikasi Flutter:
  // pilih shard rawak yang belum diketahui penuh, transaksi +1, cuba semula
  // dengan backoff + jitter jika bertembung.
  const participantRef = doc(db, `programs/${PID}/participants/${uidOf(i)}`);
  const p = profile(i);
  const knownFull = new Set();
  for (let attempt = 1; attempt <= 12; attempt++) {
    const open = [...Array(SHARDS).keys()].map(shardId).filter((id) => !knownFull.has(id));
    if (!open.length) return 'full';
    const shard = open[Math.floor(Math.random() * open.length)];
    const seatRef = doc(db, `program_seats/${PID}/shards/${shard}`);
    try {
      const result = await runTransaction(db, async (tx) => {
        const existing = await tx.get(participantRef);
        if (existing.exists()) return 'already_joined';
        const seat = await tx.get(seatRef);
        const { count, cap } = seat.data();
        if (count >= cap) return 'shard_full';
        tx.update(seatRef, { count: count + 1 });
        tx.set(participantRef, {
          studentUid: p.uid, studentName: p.fullName, studentEmail: p.email, matricNo: p.matricNo,
          course: p.course, semester: p.semester, studentPhone: p.phone, parentName: p.parentName,
          parentEmail: p.parentEmail, parentPhone: p.parentPhone, relationship: p.relationship,
          programId: PID, programTitle: 'Hari Kerjaya 2026', programDate: '2026-12-01',
          programTime: '09:00', programLocation: 'Dewan Utama', joinedAt: serverTimestamp(),
          emailStatus: 'pending', emailUpdatedAt: serverTimestamp(), seatShard: shard,
        });
        return 'success';
      }, { maxAttempts: 3 });
      if (result === 'shard_full') {
        await refreshFullShards(db, knownFull);
        continue;
      }
      return result;
    } catch (e) {
      const code = e?.code ?? '';
      if (code === 'permission-denied') {
        // Rules menolak: sudah sertai / shard penuh / bertembung. Semak status sebenar.
        if ((await getDoc(participantRef)).exists()) return 'already_joined';
        await refreshFullShards(db, knownFull);
      }
      if (attempt === 12) return `error:${code || e.message}`;
      await sleep(Math.round(Math.min(2000, 40 * 2 ** Math.min(attempt, 6)) * (0.5 + Math.random())));
    }
  }
  return 'error:exhausted';
}

console.log(`\n▶ ${JOINERS} pelajar menekan JOIN serentak (+${DOUBLE_TAP} tekan dua kali), kapasiti ${CAPACITY}...`);
const contexts = [...Array(JOINERS).keys()].map((i) => ({
  i,
  db: env.authenticatedContext(uidOf(i), { email: emailOf(i), email_verified: true }).firestore(),
}));
t0 = Date.now();
const joinLatencies = [];
const attempts = contexts.flatMap(({ i, db }) => (i < DOUBLE_TAP ? [{ i, db }, { i, db }] : [{ i, db }]));
const outcomes = await Promise.all(attempts.map(async ({ i, db }) => {
  const start = Date.now();
  const result = await joinWithRetry(db, i);
  joinLatencies.push(Date.now() - start);
  return { i, result };
}));
const joinSeconds = (Date.now() - t0) / 1000;
await Promise.all(contexts.map(({ db }) => db.app.delete().catch(() => {})));

const tally = outcomes.reduce((acc, { result }) => {
  const key = result.startsWith('error') ? 'error' : result;
  acc[key] = (acc[key] ?? 0) + 1;
  return acc;
}, {});
const errors = outcomes.filter((o) => o.result.startsWith('error'));

// --------------------------------------------------------------- 4. semakan
let seatCount = 0;
let participantDocs = 0;
let shardOverflow = 0;
await env.withSecurityRulesDisabled(async (c) => {
  const db = c.firestore();
  const shards = await getDocs(collection(db, `program_seats/${PID}/shards`));
  shards.forEach((s) => {
    seatCount += s.data().count;
    if (s.data().count > s.data().cap) shardOverflow++;
  });
  participantDocs = (await getCountFromServer(collection(db, `programs/${PID}/participants`))).data().count;
});

const successfulStudents = new Set(outcomes.filter((o) => o.result === 'success').map((o) => o.i));
const expectedJoined = Math.min(CAPACITY, JOINERS);

console.log(`  selesai dalam ${joinSeconds.toFixed(1)} s, p50=${percentile(joinLatencies, 50)} ms, p95=${percentile(joinLatencies, 95)} ms`);
console.log('  keputusan:', tally);
if (errors.length) console.log('  contoh ralat:', errors.slice(0, 3));

const checks = [
  ['Tiada overbooking (kaunter <= kapasiti)', seatCount <= CAPACITY && shardOverflow === 0],
  ['Program diisi penuh', seatCount === expectedJoined],
  ['Kaunter == bilangan dokumen penyertaan', seatCount === participantDocs],
  ['Tiada pelajar berjaya dua kali', successfulStudents.size === (tally.success ?? 0)],
  ['Semua pelajar mendapat jawapan (tiada ralat)', errors.length === 0],
];

console.log('\n▶ Semakan:');
let failed = 0;
for (const [label, ok] of checks) {
  console.log(`  ${ok ? '✔' : '✖'} ${label}`);
  if (!ok) failed++;
}
console.log(`\n  kaunter=${seatCount}, dokumen penyertaan=${participantDocs}, kapasiti=${CAPACITY}`);

await env.cleanup();
process.exit(failed ? 1 : 0);
