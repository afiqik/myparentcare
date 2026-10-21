import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');

export const PROJECT_ID = 'demo-myparentcare';
export const SUPER_ADMIN_EMAIL = 'admin@myparentcare.com';

export async function createEnv() {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8'),
    },
    database: {
      rules: readFileSync(resolve(root, 'database.rules.json'), 'utf8'),
    },
  });
}

/** Pengguna ujian standard. */
export const USERS = {
  alice: { uid: 'alice', email: 'alice@student.test', email_verified: true },
  bob: { uid: 'bob', email: 'bob@student.test', email_verified: true },
  unverified: { uid: 'unverified', email: 'new@student.test', email_verified: false },
  admin: { uid: 'admin1', email: 'staff@admin.test', email_verified: true },
  superAdmin: { uid: 'super1', email: SUPER_ADMIN_EMAIL, email_verified: true },
};

export function ctx(env, user) {
  if (!user) return env.unauthenticatedContext();
  return env.authenticatedContext(user.uid, {
    email: user.email,
    email_verified: user.email_verified,
    firebase: { sign_in_provider: user.provider ?? 'google.com' },
  });
}

export function completeProfile(user, overrides = {}) {
  return {
    uid: user.uid,
    email: user.email,
    role: 'student',
    status: 'active',
    authProvider: 'google',
    fullName: 'Nur Aina',
    matricNo: 'KPTM12345',
    course: 'Computer Science',
    semester: '5',
    phone: '0123456789',
    parentName: 'Puan Mariam',
    parentEmail: 'parent@example.com',
    parentPhone: '0198765432',
    relationship: 'Mother',
    profileCompletePercent: 100,
    privacyVersion: '2026-09-30',
    unreadNotifications: 0,
    ...overrides,
  };
}

/** Profil ketika pendaftaran (oleh klien), dengan cap masa pelayan. */
export function newProfilePayload(user, overrides = {}) {
  return {
    ...completeProfile(user),
    matricNo: '',
    course: '',
    semester: '',
    phone: '',
    parentName: '',
    parentEmail: '',
    parentPhone: '',
    relationship: '',
    profileCompletePercent: 30,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    consentAt: serverTimestamp(),
    ...overrides,
  };
}

export function programData(overrides = {}) {
  return {
    id: 'p1',
    title: 'Career Day',
    description: 'Meet employers',
    date: '2026-12-01',
    time: '09:00',
    location: 'Main Hall',
    capacity: 2,
    category: 'Career',
    status: 'open',
    cancellationReason: '',
    ...overrides,
  };
}

export function participantPayload(user, pid = 'p1', overrides = {}) {
  const p = completeProfile(user);
  return {
    studentUid: user.uid,
    studentName: p.fullName,
    studentEmail: user.email,
    matricNo: p.matricNo,
    course: p.course,
    semester: p.semester,
    studentPhone: p.phone,
    parentName: p.parentName,
    parentEmail: p.parentEmail,
    parentPhone: p.parentPhone,
    relationship: p.relationship,
    programId: pid,
    programTitle: 'Career Day',
    programDate: '2026-12-01',
    programTime: '09:00',
    programLocation: 'Main Hall',
    joinedAt: serverTimestamp(),
    emailStatus: 'pending',
    emailUpdatedAt: serverTimestamp(),
    seatShard: 's0',
    ...overrides,
  };
}

const now = () => Timestamp.fromDate(new Date());

/**
 * Data asas: alice & bob (pelajar lengkap), admin1 (admin), program p1
 * (kapasiti 2, dibuka), p2 (ditutup) dan kaunter tempat.
 */
export async function seed(env, { seats = 0, extra } = {}) {
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const stamp = { createdAt: now(), updatedAt: now(), consentAt: now() };
    await setDoc(doc(db, 'users/alice'), { ...completeProfile(USERS.alice), ...stamp });
    await setDoc(doc(db, 'users/bob'), { ...completeProfile(USERS.bob), ...stamp });
    await setDoc(doc(db, 'users/unverified'), { ...completeProfile(USERS.unverified), ...stamp });
    await setDoc(doc(db, 'users/admin1'), {
      ...completeProfile(USERS.admin, { role: 'admin', fullName: 'Staff Admin' }),
      ...stamp,
    });
    // p1: kapasiti 2 → shard s0 (cap 1) + s1 (cap 1). p2: ditutup.
    await setDoc(doc(db, 'programs/p1'), programData());
    await setDoc(doc(db, 'program_seats/p1/shards/s0'), { count: seats, cap: 1 });
    await setDoc(doc(db, 'program_seats/p1/shards/s1'), { count: 0, cap: 1 });
    await setDoc(doc(db, 'programs/p2'), programData({ id: 'p2', status: 'closed' }));
    await setDoc(doc(db, 'program_seats/p2/shards/s0'), { count: 0, cap: 2 });
    await setDoc(doc(db, 'public/catalog'), { programs: {}, announcements: {} });
    if (extra) await extra(db);
  });
}

export async function seedRtdb(env, fn) {
  await env.withSecurityRulesDisabled(async (c) => {
    await fn(c.database());
  });
}
