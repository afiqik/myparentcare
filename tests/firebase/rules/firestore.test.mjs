import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  Bytes,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import {
  USERS,
  createEnv,
  ctx,
  newProfilePayload,
  participantPayload,
  seed,
} from './helpers.mjs';

let env;

before(async () => {
  env = await createEnv();
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seed(env);
});

const db = (user) => ctx(env, user).firestore();

/** Transaksi sertai program sama seperti aplikasi Flutter. */
async function join(user, pid = 'p1', overrides = {}, shard = 's0') {
  const f = db(user);
  return runTransaction(f, async (tx) => {
    const seatRef = doc(f, `program_seats/${pid}/shards/${shard}`);
    const seat = await tx.get(seatRef);
    tx.update(seatRef, { count: seat.data().count + 1 });
    tx.set(
      doc(f, `programs/${pid}/participants/${user.uid}`),
      participantPayload(user, pid, { seatShard: shard, ...overrides }),
    );
  });
}

describe('Tanpa log masuk', () => {
  it('tidak boleh membaca katalog, profil atau program', async () => {
    const f = db(null);
    await assertFails(getDoc(doc(f, 'public/catalog')));
    await assertFails(getDoc(doc(f, 'users/alice')));
    await assertFails(getDoc(doc(f, 'programs/p1')));
    await assertFails(getDoc(doc(f, 'program_seats/p1/shards/s0')));
  });
});

describe('users/{uid} – profil & peranan', () => {
  it('pelajar baharu boleh mencipta profil sendiri sebagai student', async () => {
    const user = { uid: 'carol', email: 'carol@student.test', email_verified: false };
    await assertSucceeds(setDoc(doc(db(user), 'users/carol'), newProfilePayload(user)));
  });

  it('akaun emel/kata laluan TIDAK boleh mencipta profil (Google sahaja)', async () => {
    const user = { uid: 'pw', email: 'pw@student.test', email_verified: true, provider: 'password' };
    await assertFails(setDoc(doc(db(user), 'users/pw'), newProfilePayload(user)));
    const google = { uid: 'gg', email: 'gg@student.test', email_verified: true };
    await assertFails(setDoc(doc(db(google), 'users/gg'), newProfilePayload(google, { authProvider: 'password' })));
  });

  it('tidak boleh mendaftar sendiri sebagai admin', async () => {
    const user = { uid: 'mallory', email: 'mallory@student.test', email_verified: true };
    await assertFails(setDoc(doc(db(user), 'users/mallory'), newProfilePayload(user, { role: 'admin' })));
  });

  it('tidak boleh mencipta profil untuk uid lain atau dengan emel lain', async () => {
    const user = { uid: 'carol', email: 'carol@student.test', email_verified: true };
    await assertFails(setDoc(doc(db(user), 'users/dave'), newProfilePayload({ ...user, uid: 'dave' })));
    await assertFails(setDoc(doc(db(user), 'users/carol'), newProfilePayload(user, { email: 'x@y.com' })));
  });

  it('tidak boleh menyelitkan medan asing semasa mendaftar', async () => {
    const user = { uid: 'carol', email: 'carol@student.test', email_verified: true };
    await assertFails(setDoc(doc(db(user), 'users/carol'), newProfilePayload(user, { isAdmin: true })));
  });

  it('super admin (emel disahkan) boleh mencipta profil admin', async () => {
    const su = USERS.superAdmin;
    await assertSucceeds(setDoc(doc(db(su), `users/${su.uid}`), newProfilePayload(su, { role: 'admin' })));
  });

  it('emel super admin yang BELUM disahkan tidak boleh menjadi admin', async () => {
    const su = { ...USERS.superAdmin, email_verified: false };
    await assertFails(setDoc(doc(db(su), `users/${su.uid}`), newProfilePayload(su, { role: 'admin' })));
  });

  it('pelajar boleh mengemas kini profil sendiri', async () => {
    await assertSucceeds(updateDoc(doc(db(USERS.alice), 'users/alice'), {
      phone: '0111111111',
      updatedAt: serverTimestamp(),
    }));
  });

  it('pelajar tidak boleh menukar role, status atau emel sendiri', async () => {
    const ref = doc(db(USERS.alice), 'users/alice');
    await assertFails(updateDoc(ref, { role: 'admin', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { status: 'active', role: 'admin' }));
    await assertFails(updateDoc(ref, { email: 'other@x.com', updatedAt: serverTimestamp() }));
  });

  it('pelajar tidak boleh membaca profil pelajar lain', async () => {
    await assertFails(getDoc(doc(db(USERS.alice), 'users/bob')));
    await assertFails(getDocs(collection(db(USERS.alice), 'users')));
  });

  it('admin boleh membaca semua profil dan menggantung pelajar', async () => {
    await assertSucceeds(getDoc(doc(db(USERS.admin), 'users/bob')));
    await assertSucceeds(getDocs(collection(db(USERS.admin), 'users')));
    await assertSucceeds(updateDoc(doc(db(USERS.admin), 'users/bob'), {
      status: 'suspended',
      updatedAt: serverTimestamp(),
    }));
  });

  it('admin biasa tidak boleh menaikkan pelajar kepada admin', async () => {
    await assertFails(updateDoc(doc(db(USERS.admin), 'users/bob'), {
      role: 'admin',
      updatedAt: serverTimestamp(),
    }));
  });

  it('super admin boleh menukar peranan pengguna', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'users/super1'), {
        ...newProfilePayload(USERS.superAdmin, { role: 'admin' }),
        createdAt: new Date(), updatedAt: new Date(), consentAt: new Date(),
      });
    });
    await assertSucceeds(updateDoc(doc(db(USERS.superAdmin), 'users/bob'), {
      role: 'admin',
      updatedAt: serverTimestamp(),
    }));
  });

  it('pelajar digantung tidak boleh mengemas kini profil', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'users/bob'), { status: 'suspended' });
    });
    await assertFails(updateDoc(doc(db(USERS.bob), 'users/bob'), {
      phone: '0100000000',
      updatedAt: serverTimestamp(),
    }));
  });

  it('pelajar boleh memadam profil sendiri, admin tidak boleh dipadam oleh pelajar', async () => {
    await assertSucceeds(deleteDoc(doc(db(USERS.alice), 'users/alice')));
    await assertFails(deleteDoc(doc(db(USERS.bob), 'users/admin1')));
  });
});

describe('Katalog & program', () => {
  it('pelajar boleh membaca katalog tetapi tidak boleh menulis', async () => {
    await assertSucceeds(getDoc(doc(db(USERS.alice), 'public/catalog')));
    await assertFails(setDoc(doc(db(USERS.alice), 'public/catalog'), { programs: {} }));
  });

  it('pelajar tidak boleh membaca dokumen program penuh (termasuk draf)', async () => {
    await assertFails(getDoc(doc(db(USERS.alice), 'programs/p1')));
    await assertFails(getDocs(collection(db(USERS.alice), 'programs')));
  });

  it('admin boleh mencipta program dan kaunter tempat', async () => {
    const f = db(USERS.admin);
    const batch = writeBatch(f);
    batch.set(doc(f, 'programs/p9'), {
      id: 'p9', title: 'Futsal', description: '', date: '2026-12-10', time: '17:00',
      location: 'Court', capacity: 20, category: 'Sports', status: 'draft', cancellationReason: '',
    });
    batch.set(doc(f, 'program_seats/p9/shards/s0'), { count: 0, cap: 10 });
    batch.set(doc(f, 'program_seats/p9/shards/s1'), { count: 0, cap: 10 });
    batch.update(doc(f, 'public/catalog'), { updatedAt: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });

  it('admin tidak boleh menyimpan program dengan kapasiti tidak sah', async () => {
    await assertFails(setDoc(doc(db(USERS.admin), 'programs/bad'), {
      id: 'bad', title: 'X', description: '', date: '2026-12-10', time: '17:00',
      location: 'Hall', capacity: 0, category: 'Sports', status: 'open', cancellationReason: '',
    }));
  });
});

describe('Sertai program (kapasiti & satu tempat seorang)', () => {
  it('pelajar lengkap & emel disahkan boleh menyertai', async () => {
    await assertSucceeds(join(USERS.alice));
  });

  it('tidak boleh mencipta penyertaan tanpa menaikkan kaunter', async () => {
    await assertFails(setDoc(
      doc(db(USERS.alice), 'programs/p1/participants/alice'),
      participantPayload(USERS.alice),
    ));
  });

  it('tidak boleh menaikkan kaunter tanpa penyertaan', async () => {
    await assertFails(updateDoc(doc(db(USERS.alice), 'program_seats/p1/shards/s0'), { count: increment(1) }));
  });

  it('pelajar tidak boleh mengubah had shard (cap)', async () => {
    await assertFails(updateDoc(doc(db(USERS.alice), 'program_seats/p1/shards/s0'), { cap: 999 }));
  });

  it('penyertaan mesti merujuk shard yang sama yang dinaikkan', async () => {
    await assertFails(join(USERS.alice, 'p1', { seatShard: 's1' }, 's0'));
  });

  it('shard yang penuh menolak, shard lain masih boleh', async () => {
    await assertSucceeds(join(USERS.alice, 'p1', {}, 's0'));
    await assertFails(join(USERS.bob, 'p1', {}, 's0'));
    await assertSucceeds(join(USERS.bob, 'p1', {}, 's1'));
  });

  it('tidak boleh menyertai dua kali', async () => {
    await assertSucceeds(join(USERS.alice));
    await assertFails(join(USERS.alice));
  });

  it('tidak boleh melebihi kapasiti', async () => {
    await assertSucceeds(join(USERS.alice, 'p1', {}, 's0'));
    await assertSucceeds(join(USERS.bob, 'p1', {}, 's1'));
    const carol = { uid: 'carol', email: 'carol@student.test', email_verified: true };
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'users/carol'), {
        ...newProfilePayload(carol),
        matricNo: 'K1', course: 'CS', semester: '1', phone: '0123', parentName: 'P',
        parentEmail: 'parent@example.com', parentPhone: '0199', relationship: 'Father',
        profileCompletePercent: 100, createdAt: new Date(), updatedAt: new Date(), consentAt: new Date(),
      });
    });
    await assertFails(join(carol, 'p1', {}, 's0'));
    await assertFails(join(carol, 'p1', {}, 's1'));
  });

  it('tidak boleh menyertai program yang ditutup', async () => {
    await assertFails(join(USERS.alice, 'p2', { programId: 'p2' }));
  });

  it('emel belum disahkan tidak boleh menyertai', async () => {
    await assertFails(join(USERS.unverified));
  });

  it('profil tidak lengkap tidak boleh menyertai', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'users/alice'), { parentName: '' });
    });
    await assertFails(join(USERS.alice));
  });

  it('emel ibu bapa mesti sama dengan profil', async () => {
    await assertFails(join(USERS.alice, 'p1', { parentEmail: 'attacker@evil.test' }));
  });

  it('pelajar boleh melihat penyertaan sendiri sahaja', async () => {
    await join(USERS.alice, 'p1', {}, 's0');
    await join(USERS.bob, 'p1', {}, 's1');
    await assertSucceeds(getDoc(doc(db(USERS.alice), 'programs/p1/participants/alice')));
    await assertFails(getDoc(doc(db(USERS.alice), 'programs/p1/participants/bob')));
    await assertFails(getDocs(collection(db(USERS.alice), 'programs/p1/participants')));
    await assertSucceeds(getDocs(query(
      collectionGroup(db(USERS.alice), 'participants'),
      where('studentUid', '==', 'alice'),
    )));
    await assertFails(getDocs(query(
      collectionGroup(db(USERS.alice), 'participants'),
      where('studentUid', '==', 'bob'),
    )));
  });

  it('pelajar hanya boleh mengemas kini status emel penyertaan sendiri', async () => {
    await join(USERS.alice);
    const ref = doc(db(USERS.alice), 'programs/p1/participants/alice');
    await assertSucceeds(updateDoc(ref, { emailStatus: 'sent', emailUpdatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { parentEmail: 'x@y.com' }));
  });

  it('pelajar keluar mesti menurunkan kaunter', async () => {
    await join(USERS.alice);
    await assertFails(deleteDoc(doc(db(USERS.alice), 'programs/p1/participants/alice')));
    const f = db(USERS.alice);
    const batch = writeBatch(f);
    batch.delete(doc(f, 'programs/p1/participants/alice'));
    batch.update(doc(f, 'program_seats/p1/shards/s0'), { count: increment(-1) });
    await assertSucceeds(batch.commit());
  });

  it('pelajar tidak boleh menurunkan shard orang lain semasa keluar', async () => {
    await join(USERS.alice, 'p1', {}, 's0');
    await join(USERS.bob, 'p1', {}, 's1');
    const f = db(USERS.alice);
    const batch = writeBatch(f);
    batch.delete(doc(f, 'programs/p1/participants/alice'));
    batch.update(doc(f, 'program_seats/p1/shards/s1'), { count: increment(-1) });
    await assertFails(batch.commit());
  });

  it('admin boleh mencari emel tertangguh merentas semua program (collection group)', async () => {
    await join(USERS.alice, 'p1', {}, 's0');
    await join(USERS.bob, 'p1', {}, 's1');
    const pending = await getDocs(query(
      collectionGroup(db(USERS.admin), 'participants'),
      where('emailStatus', '==', 'pending'),
    ));
    if (pending.size !== 2) throw new Error(`expected 2 pending, got ${pending.size}`);
    await assertFails(getDocs(query(
      collectionGroup(db(USERS.alice), 'participants'),
      where('emailStatus', '==', 'pending'),
    )));
  });

  it('pelajar menyertai beberapa program dan melihat semuanya (collection group)', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const f = c.firestore();
      await setDoc(doc(f, 'programs/p3'), { id: 'p3', title: 'Futsal', description: '', date: '2026-12-10',
        time: '17:00', location: 'Court', capacity: 5, category: 'Sports', status: 'open', cancellationReason: '' });
      await setDoc(doc(f, 'program_seats/p3/shards/s0'), { count: 0, cap: 5 });
    });
    await join(USERS.alice, 'p1', {}, 's0');
    await join(USERS.alice, 'p3', { programId: 'p3' }, 's0');
    const mine = await getDocs(query(
      collectionGroup(db(USERS.alice), 'participants'),
      where('studentUid', '==', 'alice'),
    ));
    if (mine.size !== 2) throw new Error(`expected 2 participations, got ${mine.size}`);
  });

  it('admin boleh membuang peserta dan membetulkan kaunter', async () => {
    await join(USERS.alice);
    const f = db(USERS.admin);
    await assertSucceeds(getDocs(collection(f, 'programs/p1/participants')));
    const batch = writeBatch(f);
    batch.delete(doc(f, 'programs/p1/participants/alice'));
    batch.update(doc(f, 'program_seats/p1/shards/s0'), { count: increment(-1) });
    await assertSucceeds(batch.commit());
  });
});

describe('Notifikasi pelajar', () => {
  const note = (id) => ({
    id, type: 'update', title: 'Program dikemas kini', message: 'Masa baharu',
    programId: 'p1', createdAt: serverTimestamp(), isRead: false,
  });

  it('admin mencipta; pemilik membaca & menanda dibaca; orang lain ditolak', async () => {
    await assertSucceeds(setDoc(doc(db(USERS.admin), 'users/alice/notifications/n1'), note('n1')));
    await assertSucceeds(getDocs(collection(db(USERS.alice), 'users/alice/notifications')));
    await assertFails(getDocs(collection(db(USERS.bob), 'users/alice/notifications')));
    await assertSucceeds(updateDoc(doc(db(USERS.alice), 'users/alice/notifications/n1'), { isRead: true }));
    await assertFails(updateDoc(doc(db(USERS.alice), 'users/alice/notifications/n1'), { title: 'x' }));
  });

  it('pelajar tidak boleh mencipta notifikasi', async () => {
    await assertFails(setDoc(doc(db(USERS.alice), 'users/alice/notifications/n2'), note('n2')));
    await assertFails(setDoc(doc(db(USERS.alice), 'users/bob/notifications/n3'), note('n3')));
  });

  it('pelajar boleh mengosongkan kiraan belum dibaca sahaja', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await updateDoc(doc(c.firestore(), 'users/alice'), { unreadNotifications: 3 });
    });
    await assertSucceeds(updateDoc(doc(db(USERS.alice), 'users/alice'), { unreadNotifications: 0 }));
    await assertFails(updateDoc(doc(db(USERS.bob), 'users/bob'), { unreadNotifications: 99 }));
  });
});

describe('email_logs', () => {
  const log = (id, overrides = {}) => ({
    id, recipient: 'parent@example.com', subject: 'Penyertaan disahkan', body: 'Hai',
    status: 'sent', errorMessage: '', studentName: 'Nur Aina', studentUid: 'alice',
    programId: 'p1', programTitle: 'Career Day', type: 'join', createdBy: 'alice',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), attempts: 1, ...overrides,
  });

  it('pelajar merekod log emel penyertaan sendiri', async () => {
    await join(USERS.alice);
    await assertSucceeds(setDoc(doc(db(USERS.alice), 'email_logs/e1'), log('e1')));
  });

  it('pelajar tidak boleh menghantar log ke penerima lain atau jenis lain', async () => {
    await join(USERS.alice);
    await assertFails(setDoc(doc(db(USERS.alice), 'email_logs/e2'), log('e2', { recipient: 'spam@evil.test' })));
    await assertFails(setDoc(doc(db(USERS.alice), 'email_logs/e3'), log('e3', { type: 'cancelled' })));
  });

  it('pelajar tanpa penyertaan tidak boleh mencipta log', async () => {
    await assertFails(setDoc(doc(db(USERS.alice), 'email_logs/e4'), log('e4')));
  });

  it('hanya admin boleh membaca semua log emel', async () => {
    await join(USERS.alice);
    await setDoc(doc(db(USERS.alice), 'email_logs/e1'), log('e1'));
    await assertFails(getDoc(doc(db(USERS.alice), 'email_logs/e1')));
    await assertFails(getDocs(collection(db(USERS.bob), 'email_logs')));
    await assertSucceeds(getDocs(collection(db(USERS.admin), 'email_logs')));
    await assertSucceeds(getDocs(query(
      collection(db(USERS.alice), 'email_logs'),
      where('studentUid', '==', 'alice'),
    )));
  });
});

describe('media (gambar dalam Firestore, video sebagai pautan)', () => {
  const image = (id, size) => ({
    id, programId: 'p1', kind: 'image', bytes: Bytes.fromUint8Array(new Uint8Array(size)),
    contentType: 'image/jpeg', sizeBytes: size, width: 800, height: 600, url: '',
    caption: 'Poster', uploadedBy: 'admin1', createdAt: serverTimestamp(),
  });

  it('admin boleh memuat naik gambar termampat', async () => {
    await assertSucceeds(setDoc(doc(db(USERS.admin), 'media/m1'), image('m1', 200000)));
  });

  it('gambar melebihi had ditolak', async () => {
    await assertFails(setDoc(doc(db(USERS.admin), 'media/m2'), image('m2', 960000)));
  });

  it('pelajar boleh melihat tetapi tidak boleh memuat naik media', async () => {
    await setDoc(doc(db(USERS.admin), 'media/m1'), image('m1', 1000));
    await assertSucceeds(getDoc(doc(db(USERS.alice), 'media/m1')));
    await assertFails(setDoc(doc(db(USERS.alice), 'media/m3'), { ...image('m3', 10), uploadedBy: 'alice' }));
  });

  it('video mesti pautan https', async () => {
    const video = (id, url) => ({
      id, programId: 'p1', kind: 'video', url, caption: 'Video', uploadedBy: 'admin1',
      createdAt: serverTimestamp(), contentType: 'video/link', sizeBytes: 0, width: 0, height: 0,
    });
    await assertSucceeds(setDoc(doc(db(USERS.admin), 'media/v1'), video('v1', 'https://youtu.be/abc')));
    await assertFails(setDoc(doc(db(USERS.admin), 'media/v2'), video('v2', 'javascript:alert(1)')));
  });
});

describe('Pemulihan backup (super admin sahaja)', () => {
  const seedSuper = () => env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'users/super1'), {
      ...newProfilePayload(USERS.superAdmin, { role: 'admin' }),
      createdAt: new Date(), updatedAt: new Date(), consentAt: new Date(),
    });
  });

  it('super admin boleh menulis mana-mana dokumen semasa pulih', async () => {
    await seedSuper();
    const f = db(USERS.superAdmin);
    await assertSucceeds(setDoc(doc(f, 'users/restored'), { uid: 'restored', role: 'student' }));
    await assertSucceeds(setDoc(doc(f, 'programs/p1/participants/restored'), { studentUid: 'restored' }));
  });

  it('admin biasa TIDAK boleh menggunakan laluan pulih', async () => {
    await assertFails(setDoc(doc(db(USERS.admin), 'users/restored'), { uid: 'restored', role: 'admin' }));
  });

  it('super admin yang tidak aktif sebagai admin ditolak', async () => {
    await assertFails(setDoc(doc(db(USERS.superAdmin), 'users/restored'), { uid: 'restored' }));
  });
});

describe('Laporan ralat & rekod padam akaun', () => {
  it('pengguna log masuk boleh menghantar laporan ralat tetapi tidak boleh membacanya', async () => {
    const f = db(USERS.alice);
    await assertSucceeds(setDoc(doc(f, 'error_reports/r1'), {
      message: 'Boom', error: 'StateError', stackTrace: '', platform: 'android',
      appVersion: '1.0.0', uid: 'alice', createdAt: serverTimestamp(),
    }));
    await assertFails(getDoc(doc(f, 'error_reports/r1')));
    await assertSucceeds(getDoc(doc(db(USERS.admin), 'error_reports/r1')));
  });

  it('rekod pemadaman akaun tidak menyimpan data peribadi', async () => {
    const f = db(USERS.alice);
    await assertSucceeds(setDoc(doc(f, 'account_deletions/d1'), {
      createdAt: serverTimestamp(), reason: 'Tamat pengajian', role: 'student',
    }));
    await assertFails(setDoc(doc(f, 'account_deletions/d2'), {
      createdAt: serverTimestamp(), reason: '', role: 'student', email: 'alice@student.test',
    }));
  });
});
