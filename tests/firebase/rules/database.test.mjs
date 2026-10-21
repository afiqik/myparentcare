import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { get, push, ref, remove, serverTimestamp, set, update } from 'firebase/database';
import { USERS, createEnv, ctx, seedRtdb } from './helpers.mjs';

let env;

before(async () => {
  env = await createEnv();
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearDatabase();
  await seedRtdb(env, async (db) => {
    await set(ref(db, 'admins/admin1'), true);
    await set(ref(db, 'admin_workspace/audit_logs/seed'), {
      action: 'seed', actorUid: 'admin1', actorEmail: 'staff@admin.test', summary: 'seed', at: 1,
    });
    // Data versi lama (sebelum migrasi) yang dahulunya terbuka kepada umum.
    await set(ref(db, 'users/alice'), { fullName: 'Nur Aina', parentEmail: 'parent@example.com' });
  });
});

const rtdb = (user) => ctx(env, user).database();

const auditEntry = (user, overrides = {}) => ({
  action: 'program.create',
  actorUid: user.uid,
  actorEmail: user.email,
  summary: 'Cipta program Career Day',
  targetType: 'program',
  targetId: 'p1',
  at: serverTimestamp(),
  ...overrides,
});

describe('RTDB: data lama tidak lagi terbuka kepada umum', () => {
  it('tanpa log masuk tidak boleh membaca apa-apa', async () => {
    await assertFails(get(ref(rtdb(null), '/')));
    await assertFails(get(ref(rtdb(null), 'users')));
  });

  it('pelajar tidak boleh membaca data lama', async () => {
    await assertFails(get(ref(rtdb(USERS.alice), 'users')));
  });

  it('admin boleh membaca data lama untuk migrasi', async () => {
    await assertSucceeds(get(ref(rtdb(USERS.admin), 'users')));
  });
});

describe('RTDB: ruang kerja admin terasing daripada pelajar', () => {
  it('pelajar tidak boleh membaca atau menulis ruang kerja admin', async () => {
    const db = rtdb(USERS.alice);
    await assertFails(get(ref(db, 'admin_workspace')));
    await assertFails(get(ref(db, 'admin_workspace/audit_logs')));
    await assertFails(push(ref(db, 'admin_workspace/audit_logs'), auditEntry(USERS.alice)));
  });

  it('admin boleh membaca ruang kerja dan menambah log audit', async () => {
    const db = rtdb(USERS.admin);
    await assertSucceeds(get(ref(db, 'admin_workspace')));
    await assertSucceeds(push(ref(db, 'admin_workspace/audit_logs'), auditEntry(USERS.admin)));
  });

  it('log audit tidak boleh diubah atau dipadam (append-only)', async () => {
    const db = rtdb(USERS.admin);
    await assertFails(update(ref(db, 'admin_workspace/audit_logs/seed'), { summary: 'diubah' }));
    await assertFails(remove(ref(db, 'admin_workspace/audit_logs/seed')));
  });

  it('log audit mesti atas nama admin yang sebenar', async () => {
    const db = rtdb(USERS.admin);
    await assertFails(push(ref(db, 'admin_workspace/audit_logs'), auditEntry(USERS.admin, { actorUid: 'someone-else' })));
    await assertFails(push(ref(db, 'admin_workspace/audit_logs'), auditEntry(USERS.admin, { hacked: true })));
  });

  it('presence: admin hanya boleh menulis status dirinya', async () => {
    const db = rtdb(USERS.admin);
    await assertSucceeds(set(ref(db, 'admin_workspace/presence/admin1'), {
      online: true, lastSeen: serverTimestamp(), email: USERS.admin.email, name: 'Staff',
    }));
    await assertFails(set(ref(db, 'admin_workspace/presence/other'), {
      online: true, lastSeen: serverTimestamp(),
    }));
  });

  it('rekod backup: append-only dan atas nama sendiri', async () => {
    const db = rtdb(USERS.admin);
    const record = {
      at: serverTimestamp(), by: 'admin1', byEmail: USERS.admin.email,
      documents: 42, bytes: 1024, kind: 'backup',
    };
    await assertSucceeds(set(ref(db, 'admin_workspace/backups/b1'), record));
    await assertFails(set(ref(db, 'admin_workspace/backups/b1'), record));
    await assertFails(set(ref(db, 'admin_workspace/backups/b2'), { ...record, by: 'x' }));
  });
});

describe('RTDB: tetapan EmailJS (private key) – admin sahaja', () => {
  const setting = (uid) => ({ privateKey: 'k'.repeat(21), updatedBy: uid, updatedAt: serverTimestamp() });

  it('admin boleh menyimpan & membaca private key', async () => {
    const db = rtdb(USERS.admin);
    await assertSucceeds(set(ref(db, 'admin_workspace/settings/emailjs'), setting('admin1')));
    await assertSucceeds(get(ref(db, 'admin_workspace/settings/emailjs')));
  });

  it('pelajar & pengguna tanpa log masuk tidak boleh membaca atau menulis private key', async () => {
    await assertFails(get(ref(rtdb(USERS.alice), 'admin_workspace/settings/emailjs')));
    await assertFails(get(ref(rtdb(null), 'admin_workspace/settings/emailjs')));
    await assertFails(set(ref(rtdb(USERS.alice), 'admin_workspace/settings/emailjs'), setting('alice')));
  });

  it('nilai tidak sah / medan asing ditolak', async () => {
    const db = rtdb(USERS.admin);
    await assertFails(set(ref(db, 'admin_workspace/settings/emailjs'), { ...setting('admin1'), privateKey: 'x' }));
    await assertFails(set(ref(db, 'admin_workspace/settings/emailjs'), { ...setting('admin1'), extra: 1 }));
    await assertFails(set(ref(db, 'admin_workspace/settings/emailjs'), setting('someone-else')));
  });
});

describe('RTDB: senarai admin', () => {
  it('pengguna boleh menyemak status admin dirinya sahaja', async () => {
    await assertSucceeds(get(ref(rtdb(USERS.alice), 'admins/alice')));
    await assertFails(get(ref(rtdb(USERS.alice), 'admins')));
    await assertSucceeds(get(ref(rtdb(USERS.admin), 'admins')));
  });

  it('pelajar dan admin biasa tidak boleh melantik admin', async () => {
    await assertFails(set(ref(rtdb(USERS.alice), 'admins/alice'), true));
    await assertFails(set(ref(rtdb(USERS.admin), 'admins/bob'), true));
  });

  it('super admin (emel disahkan) boleh melantik dan melucutkan admin', async () => {
    const db = rtdb(USERS.superAdmin);
    await assertSucceeds(set(ref(db, 'admins/super1'), true));
    await assertSucceeds(set(ref(db, 'admins/bob'), true));
    await assertSucceeds(remove(ref(db, 'admins/bob')));
  });

  it('super admin yang emelnya belum disahkan ditolak', async () => {
    await assertFails(set(ref(rtdb({ ...USERS.superAdmin, email_verified: false }), 'admins/super1'), true));
  });
});
