/**
 * MyParentCare – automasi percuma dengan Google Apps Script (kekal pelan Spark).
 *
 *  1. Emel SEGERA – skrip ini juga "web app". Sejurus selepas pelajar join,
 *     aplikasi pelajar memanggil doPost() dan emel pengesahan dihantar kepada
 *     ibu bapa dalam beberapa saat melalui EmailJS yang SAMA seperti aplikasi
 *     (servis, templat dan private key yang sama).
 *  2. processEmails()  – setiap 5 minit (sandaran): hantar mana-mana emel yang
 *     masih "pending" (contoh: telefon pelajar hilang internet) dan emel dalam
 *     barisan (email_logs "queued"). Aplikasi admin tidak perlu dibuka.
 *  3. dailyBackup()    – setiap hari ~3 pagi: backup penuh Firestore + RTDB ke
 *     Google Drive. Format fail sama dengan backup aplikasi, jadi boleh
 *     dipulihkan daripada Admin tools → Backup & restore.
 *
 * Skrip berjalan sebagai pemilik projek Firebase (OAuth Google). Private key
 * EmailJS dibaca terus daripada ruang kerja admin RTDB – tidak disalin ke
 * sini, tidak dicetak dalam log dan tidak dimasukkan ke dalam backup.
 *
 * Web app hanya boleh MEMPERCEPAT emel pengesahan yang sudah menunggu untuk
 * penyertaan sebenar (dibaca semula daripada Firestore). Ia tidak menerima
 * alamat emel atau kandungan daripada pemanggil, jadi tidak boleh disalah guna
 * untuk menghantar emel lain.
 *
 * Pemasangan: lihat apps_script/README.md. Fungsi yang dijalankan manual:
 *   setup()        – pasang trigger, simpan pautan web app, semak sambungan
 *   checkSetup()   – semak sambungan sahaja
 *   testEmail()    – hantar satu emel ujian EmailJS ke akaun anda
 *   dailyBackup()  – buat backup sekarang
 *   removeTriggers() – hentikan automasi berjadual
 */

/** Jalankan fungsi ini sekali (▶ Run) selepas pasang: trigger + pautan web app + semakan. */
function setup() {
  removeTriggers_();
  ScriptApp.newTrigger('processEmails').timeBased().everyMinutes(CONFIG.emailEveryMinutes).create();
  ScriptApp.newTrigger('dailyBackup').timeBased().everyDays(1).atHour(CONFIG.backupHour).create();
  try {
    saveWebAppUrl_();
  } catch (error) {
    console.error('Simpan pautan web app gagal: ' + error);
  }
  return checkSetup();
}

var SCRIPT_VERSION = 2;

var CONFIG = {
  projectId: 'myparentcare-45eb1',
  firestoreBase: 'https://firestore.googleapis.com/v1',
  rtdbUrl: 'https://myparentcare-45eb1-default-rtdb.asia-southeast1.firebasedatabase.app',
  rtdbQuery: '',
  emailJs: {
    endpoint: 'https://api.emailjs.com/api/v1.0/email/send',
    serviceId: 'service_aeph2e8',
    templateId: 'template_pbwdb3p',
    publicKey: 'nIq9l3JATYQyg179z',
  },
  // Emel
  emailEveryMinutes: 5,
  maxEmailsPerRun: 25,
  emailSpacingMs: 1100,
  // Emel segera: jika giliran EmailJS terlalu panjang, biar trigger 5 minit menghantar.
  maxInstantWaitMs: 15000,
  maxRequestsPerMinute: 300,
  // Jika admin sedang membuka aplikasi, beri aplikasi peluang menghantar dahulu.
  adminGraceMinutes: 3,
  // Ralat sementara (429/5xx/rangkaian): maklumkan pelajar hanya jika tertangguh selama ini.
  delayNoticeMinutes: 15,
  logCreatedBy: 'apps-script',
  // Backup
  backupHour: 3,
  backupFolderName: 'MyParentCare Backups',
  keepDailyDays: 30,
  keepWeeklyDays: 90,
  backupReadBudget: 20000,
  maxFileChars: 45 * 1024 * 1024,
  // Amaran kepada pemilik (Gmail sendiri, bukan kepada ibu bapa)
  alertEmail: '',
  alertEveryHours: 12,
};

var BACKUP_FORMAT = 'myparentcare-backup';
var BACKUP_VERSION = 1;
var BACKUP_DESCRIPTION = 'MyParentCare backup automatik (Apps Script)';
var SERVICE_NAME = 'myparentcare-email';
var ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
var RELAY_URL_PATTERN = /^https:\/\/script\.google\.com\/(a\/macros\/[^/]+|macros)\/s\/[A-Za-z0-9_-]+\/exec$/;

// Susunan & bentuk sama dengan BackupService.createBackup dalam aplikasi.
var BACKUP_PARTS = [
  { key: 'users', collection: 'users' },
  { key: 'programs', collection: 'programs' },
  { key: 'program_seats', group: 'shards' },
  { key: 'participants', group: 'participants' },
  { key: 'notifications', group: 'notifications', optional: 1 },
  { key: 'public', collection: 'public' },
  { key: 'media', collection: 'media', pageSize: 10 },
  { key: 'email_logs', collection: 'email_logs', optional: 2 },
  { key: 'account_deletions', collection: 'account_deletions' },
];

// ======================================================= web app (segera)

/** Semakan kesihatan: GET <pautan web app>. */
function doGet() {
  return json_(handleRequest_({ action: 'ping' }));
}

/** Aplikasi pelajar: POST {"action":"join","programId":"…","uid":"…"}. */
function doPost(e) {
  var body = {};
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}') || {};
  } catch (ignored) {}
  return json_(handleRequest_(body));
}

function handleRequest_(body) {
  try {
    if (body.action === 'join') return sendJoinNow_(body.programId, body.uid);
    if (body.action === 'ping') {
      return {
        ok: true,
        service: SERVICE_NAME,
        version: SCRIPT_VERSION,
        keyConfigured: !!readPrivateKey_(),
        triggers: ScriptApp.getProjectTriggers().map(function (t) { return t.getHandlerFunction(); }).sort(),
      };
    }
    return { ok: false, status: 'invalid' };
  } catch (error) {
    console.error('Web app: ' + errorText_(error));
    return { ok: false, status: 'error' };
  }
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

/** Hantar emel pengesahan untuk SATU penyertaan yang masih "pending". */
function sendJoinNow_(programId, uid) {
  if (!ID_PATTERN.test(String(programId || '')) || !ID_PATTERN.test(String(uid || ''))) {
    return { ok: false, status: 'invalid' };
  }
  if (!rateAllowed_()) return { ok: true, status: 'queued' };
  var name = docName_('programs/' + programId + '/participants/' + uid);
  var key = readPrivateKey_();
  if (!key) {
    alertMissingKey_(1);
    var waiting = fsGetByName_(name);
    if (waiting && str_(waiting.fields, 'emailStatus') === 'pending') {
      notifyDelayed_(waiting, MISSING_KEY, Date.now());
    }
    return { ok: true, status: 'queued' };
  }
  var claimKey = 'p:' + name;
  if (!claim_(claimKey, 600)) return { ok: true, status: 'queued' };
  var outcome;
  try {
    outcome = sendParticipant_(name, key, {}, CONFIG.maxInstantWaitMs);
  } finally {
    // Status sudah ditulis ke Firestore; setiap laluan membaca semula sebelum hantar.
    release_(claimKey);
  }
  if (outcome.status === 'retry') return { ok: true, status: 'queued' };
  return { ok: outcome.status !== 'not_found', status: outcome.status };
}

// ============================================================== trigger

function processEmails() {
  if (!claim_('run:emails', 300)) return { busy: true };
  try {
    var result = processEmailsNow_();
    if (result.sent || result.failed) console.log('Emel: ' + JSON.stringify(result));
    return result;
  } catch (error) {
    alert_('email', 'Penghantaran emel automatik gagal', errorText_(error));
    return { error: String(error) };
  } finally {
    release_('run:emails');
  }
}

function dailyBackup() {
  if (!claim_('run:backup', 1800)) return { busy: true };
  try {
    var result = backupNow_();
    console.log('Backup: ' + JSON.stringify(result));
    return result;
  } catch (error) {
    alert_('backup', 'Backup automatik GAGAL', errorText_(error));
    return { error: String(error) };
  } finally {
    release_('run:backup');
  }
}

// ============================================================ pemasangan

function removeTriggers() {
  removeTriggers_();
  console.log('Semua trigger MyParentCare dibuang – automasi berjadual dihentikan.');
}

function removeTriggers_() {
  ScriptApp.getProjectTriggers().forEach(function (trigger) {
    var name = trigger.getHandlerFunction();
    if (name === 'processEmails' || name === 'dailyBackup') ScriptApp.deleteTrigger(trigger);
  });
}

/**
 * Jika skrip sudah di-deploy sebagai web app, sahkan pautannya menjawab dan
 * simpan dalam Firestore public/config supaya aplikasi pelajar menggunakannya.
 */
function saveWebAppUrl_() {
  var url = '';
  try {
    url = ScriptApp.getService().getUrl() || '';
  } catch (ignored) {}
  if (!RELAY_URL_PATTERN.test(url)) return null;
  var pong = pingRelay_(url);
  if (!pong || pong.service !== SERVICE_NAME) return null;
  commit_([{
    update: {
      name: docName_('public/config'),
      fields: toFields_({ emailRelayUrl: url, emailRelayUpdatedBy: CONFIG.logCreatedBy }),
    },
    updateMask: { fieldPaths: ['emailRelayUrl', 'emailRelayUpdatedBy'] },
    updateTransforms: [{ fieldPath: 'emailRelayUpdatedAt', setToServerValue: 'REQUEST_TIME' }],
  }]);
  return url;
}

function pingRelay_(url) {
  var res = http_('GET', url, null, {});
  if (res.code !== 200) return null;
  try {
    return JSON.parse(res.text);
  } catch (error) {
    return null;
  }
}

/** Semak setiap sambungan dan cetak laporan (tanpa mendedahkan private key). */
function checkSetup() {
  var lines = ['Akaun: ' + ownerEmail_()];
  var ok = true;
  function check(label, fn) {
    try {
      lines.push(label + ': ' + fn());
    } catch (error) {
      ok = false;
      lines.push(label + ': GAGAL – ' + String(error.message || error).slice(0, 300));
    }
  }
  check('Firestore', function () {
    var catalog = fsGet_('public/catalog');
    return 'OK' + (catalog ? '' : ' (public/catalog belum wujud)');
  });
  check('Realtime Database', function () {
    var online = anyAdminOnline_();
    return 'OK' + (online ? ' (admin sedang dalam talian)' : '');
  });
  check('Private key EmailJS', function () {
    if (readPrivateKey_()) return 'ADA (dibaca dari ruang kerja admin)';
    ok = false;
    return 'TIADA – tampal di aplikasi admin → Tools → Email settings';
  });
  check('Emel segera (web app)', function () {
    var config = fsGet_('public/config');
    var url = config ? str_(config.fields, 'emailRelayUrl') : '';
    if (!url) {
      ok = false;
      return 'BELUM – Deploy → New deployment → Web app (Execute as: Me, Who has access: Anyone), ' +
        'kemudian jalankan setup semula';
    }
    var pong = pingRelay_(url);
    if (!pong || pong.service !== SERVICE_NAME) {
      ok = false;
      return 'GAGAL – pautan tidak menjawab: ' + url;
    }
    return 'OK – ' + url;
  });
  check('Emel menunggu', function () {
    return pendingParticipants_().length + ' pengesahan, ' + queuedLogs_().length + ' dalam barisan';
  });
  check('Google Drive', function () {
    return 'OK – folder "' + backupFolder_().getName() + '"';
  });
  var handlers = ScriptApp.getProjectTriggers().map(function (t) { return t.getHandlerFunction(); });
  lines.push('Trigger: ' + (handlers.length ? handlers.join(', ') : 'belum dipasang – jalankan setup()'));
  lines.push(ok ? 'SEMUA OK' : 'ADA MASALAH – lihat baris GAGAL/TIADA/BELUM di atas');
  console.log(lines.join('\n'));
  return lines;
}

/** Hantar satu emel ujian melalui EmailJS ke akaun pemilik skrip. */
function testEmail() {
  var key = readPrivateKey_();
  if (!key) throw new Error('Private key EmailJS tiada di ruang kerja admin.');
  var to = CONFIG.alertEmail || ownerEmail_();
  var result = sendEmailJs_(testMessage_(to, 'Google Apps Script'), key);
  console.log(result.success ? 'Emel ujian diterima EmailJS → ' + to : 'GAGAL: ' + result.error);
  return result;
}

// ========================================================= emel ibu bapa

function processEmailsNow_() {
  var result = { sent: 0, failed: 0, waiting: 0 };
  var pending = pendingParticipants_();
  var queued = queuedLogs_();
  if (!pending.length && !queued.length) return result;

  var key = readPrivateKey_();
  if (!key) {
    result.waiting = pending.length + queued.length;
    alertMissingKey_(result.waiting);
    pending.forEach(function (doc) { notifyDelayed_(doc, MISSING_KEY, Date.now()); });
    return result;
  }

  var now = Date.now();
  var adminOnline = anyAdminOnline_();
  var graceMs = CONFIG.adminGraceMinutes * 60000;
  var budget = CONFIG.maxEmailsPerRun;
  var programs = {};

  for (var i = 0; i < pending.length && budget > 0; i++) {
    var joinedAt = tsMillis_(pending[i].fields, 'joinedAt') || now;
    if (adminOnline && now - joinedAt < graceMs) { result.waiting++; continue; }
    var claimKey = 'p:' + pending[i].name;
    // Emel segera (web app) mungkin sedang menghantar penyertaan yang sama.
    if (!claim_(claimKey, 600)) { result.waiting++; continue; }
    var outcome;
    try {
      outcome = sendParticipant_(pending[i].name, key, programs, 0);
    } finally {
      release_(claimKey);
    }
    if (outcome.status === 'retry') {
      // Maklumkan pelajar lain yang turut menunggu (sekali sahaja bagi setiap penyertaan).
      for (var k = i + 1; k < pending.length; k++) notifyDelayed_(pending[k], outcome.send, now);
      result.waiting++;
      return result;
    }
    if (outcome.sentEmail) budget--;
    if (outcome.status === 'sent' || outcome.status === 'failed') result[outcome.status]++;
  }

  for (var j = 0; j < queued.length && budget > 0; j++) {
    var createdAt = tsMillis_(queued[j].fields, 'createdAt') || now;
    if (adminOnline && now - createdAt < graceMs) { result.waiting++; continue; }
    var logClaim = 'l:' + queued[j].name;
    if (!claim_(logClaim, 600)) { result.waiting++; continue; }
    // Semak semula sejurus sebelum hantar: aplikasi admin mungkin sudah menghantarnya.
    var freshLog = fsGetByName_(queued[j].name);
    if (!freshLog || str_(freshLog.fields, 'status') !== 'queued') {
      release_(logClaim);
      continue;
    }
    var log = logFrom_(freshLog);
    waitForEmailJsSlot_(0);
    budget--;
    var send = sendEmailJs_(logMessage_(log), key);
    if (send.retryLater) {
      accountProblem_(send);
      recordAutomation_(false, send);
      release_(logClaim);
      result.waiting++;
      return result;
    }
    var status = send.success ? 'sent' : 'failed';
    recordAutomation_(true);
    try {
      commit_([logUpdateWrite_(freshLog.name, status, send.error, log.attempts + 1)]);
    } finally {
      release_(logClaim);
    }
    if (log.type === 'join' && log.programId && log.studentUid) {
      try {
        commit_([participantStatusWrite_(
          docName_('programs/' + log.programId + '/participants/' + log.studentUid), status)]);
      } catch (ignored) {}
    }
    result[status]++;
  }
  return result;
}

/**
 * Hantar emel pengesahan untuk satu dokumen peserta (dibaca semula dahulu).
 * Pulangkan { status: sent|failed|retry|not_found|<status semasa>, sentEmail }.
 */
function sendParticipant_(name, key, programs, maxWaitMs) {
  var fresh = fsGetByName_(name);
  if (!fresh) return { status: 'not_found', sentEmail: false };
  var current = str_(fresh.fields, 'emailStatus');
  if (current !== 'pending') return { status: current || 'unknown', sentEmail: false };
  var p = participantFrom_(fresh);
  var message = joinMessage_(p.parentEmail, p.studentName, programFor_(p, programs));
  if (!waitForEmailJsSlot_(maxWaitMs)) return { status: 'retry', sentEmail: false, send: BUSY };
  var send = sendEmailJs_(message, key);
  if (send.retryLater) {
    accountProblem_(send);
    recordAutomation_(false, send);
    notifyDelayed_(fresh, send, Date.now());
    return { status: 'retry', sentEmail: true, send: send };
  }
  recordAutomation_(true);
  var status = send.success ? 'sent' : 'failed';
  var logWrite = newLogWrite_(message, status, send.error, p.studentUid, p.programId, 1);
  try {
    commit_([participantStatusWrite_(fresh.name, status), logWrite]);
  } catch (error) {
    // Peserta mungkin sudah keluar program – simpan log sahaja.
    commit_([logWrite]);
    return { status: status, sentEmail: true, send: send };
  }
  if (status === 'failed') notifyFailed_(fresh, send);
  return { status: status, sentEmail: true, send: send };
}

var MISSING_KEY = {
  code: 'key',
  error: 'Private key EmailJS tiada. Tampal di aplikasi admin → Tools → Email settings.',
};
var BUSY = { code: 429, error: 'Giliran EmailJS penuh – akan dihantar oleh trigger 5 minit.' };

// ------------------------------------------- notifikasi pelajar & status admin

/**
 * Emel ditolak untuk penyertaan ini (contoh: alamat tidak sah) – maklumkan
 * pelajar dalam aplikasi. Admin melihat sebab penuh dalam Pusat Emel.
 */
function notifyFailed_(doc, send) {
  var p = participantFrom_(doc);
  var hint = send.code === 400 || send.code === 422
    ? 'Alamat emel ibu bapa mungkin tidak sah. '
    : 'Berlaku masalah pada sistem emel. ';
  return notifyStudent_(p.studentUid, 'email-failed-' + p.programId + '-' + tsMillis_(doc.fields, 'joinedAt'),
    'Emel kepada ibu bapa gagal dihantar',
    'Penyertaan anda dalam ' + p.programTitle + ' tetap disahkan, tetapi emel pengesahan kepada ' +
    p.parentEmail + ' tidak dapat dihantar. ' + hint +
    'Semak emel ibu bapa di Profil. Admin telah dimaklumkan dan boleh menghantar semula.',
    p.programId);
}

/**
 * Emel tertangguh kerana masalah akaun EmailJS / sementara. Emel kekal
 * "pending" dan dicuba semula; pelajar dimaklumkan sekali sahaja.
 */
function notifyDelayed_(doc, send, now) {
  var joinedAt = tsMillis_(doc.fields, 'joinedAt');
  var accountLevel = send.code === 'key' || [403, 412, 426].indexOf(send.code) >= 0;
  var waitedMs = now - (joinedAt || now);
  if (!accountLevel && waitedMs < CONFIG.delayNoticeMinutes * 60000) return false;
  var p = participantFrom_(doc);
  return notifyStudent_(p.studentUid, 'email-delay-' + p.programId + '-' + joinedAt,
    'Emel kepada ibu bapa tertangguh',
    'Penyertaan anda dalam ' + p.programTitle + ' telah disahkan. Emel pengesahan kepada ' +
    p.parentEmail + ' belum dapat dihantar kerana masalah sementara pada sistem emel. ' +
    'Sistem akan mencuba semula secara automatik dan admin telah dimaklumkan.',
    p.programId);
}

/** Notifikasi dalam aplikasi (sama seperti ProgramRepository._addNotification), sekali sahaja. */
function notifyStudent_(uid, id, title, message, programId) {
  if (!ID_PATTERN.test(String(uid || ''))) return false;
  var cache = CacheService.getScriptCache();
  var seenKey = 'n:' + uid + ':' + id;
  if (cache.get(seenKey)) return false;
  cache.put(seenKey, '1', 21600);
  try {
    commit_([
      {
        update: {
          name: docName_('users/' + uid + '/notifications/' + id),
          fields: toFields_({
            id: id,
            type: 'info',
            title: clip_(title, 120),
            message: clip_(message, 1000),
            programId: clip_(programId, 80),
            isRead: false,
          }),
        },
        updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
        currentDocument: { exists: false },
      },
      {
        transform: {
          document: docName_('users/' + uid),
          fieldTransforms: [{ fieldPath: 'unreadNotifications', increment: { integerValue: '1' } }],
        },
        currentDocument: { exists: true },
      },
    ]);
    return true;
  } catch (error) {
    return false; // sudah dimaklumkan sebelum ini, atau akaun sudah dipadam
  }
}

/**
 * Status automasi untuk papan pemuka admin (RTDB admin_workspace/automation/email).
 * Ditulis hanya apabila keadaan berubah supaya tidak membazir.
 */
function recordAutomation_(ok, send) {
  try {
    var cache = CacheService.getScriptCache();
    var path = 'admin_workspace/automation/email';
    if (ok) {
      if (cache.get('automation:ok')) return;
      cache.put('automation:ok', '1', 3600);
      cache.remove('automation:err');
      rtdb_('PUT', path, { ok: true, message: '', code: '', at: { '.sv': 'timestamp' } });
      return;
    }
    cache.remove('automation:ok');
    var code = String(send.code || 'network');
    if (cache.get('automation:err') === code) return;
    cache.put('automation:err', code, 600);
    rtdb_('PUT', path, { ok: false, message: clip_(send.error, 500), code: code, at: { '.sv': 'timestamp' } });
  } catch (error) {
    console.error('Status automasi gagal ditulis: ' + error);
  }
}

function accountProblem_(send) {
  // 403/412/426/5xx: masalah akaun atau sementara – emel kekal menunggu.
  if (send.code === 429) return;
  alert_('emailjs-' + (send.code || 'network'), 'EmailJS menolak penghantaran automatik',
    send.error + '\n\nEmel kekal menunggu dan akan dicuba semula secara automatik.');
}

function alertMissingKey_(waiting) {
  recordAutomation_(false, MISSING_KEY);
  alert_('emailjs-key', 'Private key EmailJS tiada',
    waiting + ' emel ibu bapa sedang menunggu. Buka aplikasi admin → Tools → ' +
    'Email settings dan tampal private key EmailJS.');
}

// ------------------------------------------- kunci, giliran & had kadar

function withLock_(fn) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return null;
  try {
    return fn();
  } finally {
    lock.releaseLock();
  }
}

/** Tuntutan sementara (tamat sendiri) supaya dua laluan tidak menghantar emel yang sama. */
function claim_(key, seconds) {
  return withLock_(function () {
    var cache = CacheService.getScriptCache();
    if (cache.get(key)) return false;
    cache.put(key, '1', seconds);
    return true;
  }) === true;
}

function release_(key) {
  CacheService.getScriptCache().remove(key);
}

/**
 * Had kadar EmailJS (~1 emel sesaat) dikongsi oleh web app & trigger: tempah
 * slot seterusnya dan tunggu. Pulangkan false jika giliran melebihi maxWaitMs.
 */
function waitForEmailJsSlot_(maxWaitMs) {
  var wait = withLock_(function () {
    var cache = CacheService.getScriptCache();
    var now = Date.now();
    var next = Math.max(now, Number(cache.get('emailjs:next') || 0));
    if (maxWaitMs && next - now > maxWaitMs) return -1;
    cache.put('emailjs:next', String(next + CONFIG.emailSpacingMs), 120);
    return next - now;
  });
  if (wait === null || wait < 0) return false;
  if (wait > 0) Utilities.sleep(wait);
  return true;
}

function rateAllowed_() {
  return withLock_(function () {
    var cache = CacheService.getScriptCache();
    var key = 'rate:' + Math.floor(Date.now() / 60000);
    var count = Number(cache.get(key) || 0) + 1;
    cache.put(key, String(count), 120);
    return count <= CONFIG.maxRequestsPerMinute;
  }) === true;
}

function pendingParticipants_() {
  return runQuery_({
    from: [{ collectionId: 'participants', allDescendants: true }],
    where: fieldEquals_('emailStatus', 'pending'),
    limit: CONFIG.maxEmailsPerRun,
  });
}

function queuedLogs_() {
  return runQuery_({
    from: [{ collectionId: 'email_logs' }],
    where: fieldEquals_('status', 'queued'),
    orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'ASCENDING' }],
    limit: CONFIG.maxEmailsPerRun,
  });
}

function participantFrom_(doc) {
  var f = doc.fields || {};
  return {
    studentUid: str_(f, 'studentUid'),
    studentName: str_(f, 'studentName'),
    parentEmail: str_(f, 'parentEmail'),
    programId: str_(f, 'programId'),
    programTitle: str_(f, 'programTitle'),
    programDate: str_(f, 'programDate'),
    programTime: str_(f, 'programTime'),
    programLocation: str_(f, 'programLocation'),
  };
}

/** Maklumat program terkini (seperti aplikasi admin); jika tiada, guna salinan peserta. */
function programFor_(p, cache) {
  if (!(p.programId in cache)) {
    var doc = p.programId ? fsGet_('programs/' + p.programId) : null;
    cache[p.programId] = doc ? {
      title: str_(doc.fields, 'title'),
      date: str_(doc.fields, 'date'),
      time: str_(doc.fields, 'time'),
      location: str_(doc.fields, 'location'),
    } : null;
  }
  return cache[p.programId] || {
    title: p.programTitle,
    date: p.programDate,
    time: p.programTime,
    location: p.programLocation,
  };
}

function logFrom_(doc) {
  var f = doc.fields || {};
  return {
    recipient: str_(f, 'recipient'),
    subject: str_(f, 'subject'),
    body: str_(f, 'body'),
    type: str_(f, 'type') || 'join',
    studentName: str_(f, 'studentName'),
    studentUid: str_(f, 'studentUid'),
    programId: str_(f, 'programId'),
    programTitle: str_(f, 'programTitle'),
    attempts: Number((f.attempts && f.attempts.integerValue) || 0),
  };
}

// ------------------------------------------------ templat (= email_templates.dart)

function ellipsis_(value, max) {
  return value.length <= max ? value : value.substring(0, max) + '…';
}

function clip_(value, max) {
  value = value || '';
  return value.length <= max ? value : value.substring(0, max);
}

/** Sama dengan EmailTemplates.join dalam aplikasi. */
function joinMessage_(parentEmail, studentName, program) {
  return {
    to: parentEmail,
    type: 'join',
    studentName: studentName,
    programTitle: program.title,
    programDate: program.date,
    programTime: program.time,
    programLocation: program.location,
    reason: '',
    subject: ellipsis_('MyParentCare: Penyertaan ' + studentName + ' disahkan', 200),
    body: [
      'Salam sejahtera,',
      '',
      studentName + ' telah menyertai program berikut:',
      '',
      'Program: ' + program.title,
      'Tarikh: ' + program.date,
      'Masa: ' + program.time,
      'Lokasi: ' + program.location,
      'Status: Disahkan',
      '',
      'Ini ialah notifikasi automatik daripada MyParentCare. Jika anda tidak mengenali pelajar ini, sila abaikan emel ini.',
    ].join('\n').trim(),
  };
}

/** Sama dengan EmailTemplates.fromLog (emel kemas kini/pembatalan dalam barisan). */
function logMessage_(log) {
  return {
    to: log.recipient,
    subject: log.subject,
    body: log.body,
    type: log.type,
    studentName: log.studentName,
    programTitle: log.programTitle,
    programDate: '',
    programTime: '',
    programLocation: '',
    reason: '',
  };
}

function testMessage_(to, adminName) {
  var sentAt = Utilities.formatDate(new Date(), 'Asia/Kuala_Lumpur', 'yyyy-MM-dd HH:mm');
  return {
    to: to,
    type: 'test',
    studentName: adminName,
    programTitle: 'Emel ujian MyParentCare',
    programDate: '',
    programTime: '',
    programLocation: '',
    reason: '',
    subject: 'MyParentCare: Emel ujian (' + sentAt + ')',
    body: [
      'Salam sejahtera,',
      '',
      'Ini ialah emel ujian daripada Pusat Emel MyParentCare.',
      '',
      'Jika anda menerima emel ini, penghantaran emel kepada ibu bapa berfungsi dengan betul.',
      '',
      'Dihantar oleh: ' + adminName,
      'Masa: ' + sentAt,
    ].join('\n'),
  };
}

// ---------------------------------------------------- EmailJS (= email_gateway.dart)

function emailJsPayload_(message, privateKey) {
  var payload = {
    service_id: CONFIG.emailJs.serviceId,
    template_id: CONFIG.emailJs.templateId,
    user_id: CONFIG.emailJs.publicKey,
  };
  if (privateKey) payload.accessToken = privateKey;
  payload.template_params = {
    to_email: message.to,
    subject: message.subject,
    message: message.body,
    student_name: message.studentName,
    program_title: message.programTitle,
    program_date: message.programDate,
    program_time: message.programTime,
    program_location: message.programLocation,
    reason: message.reason,
    type: message.type,
  };
  return payload;
}

function sendEmailJs_(message, privateKey) {
  var res;
  try {
    res = http_('POST', CONFIG.emailJs.endpoint, emailJsPayload_(message, privateKey), {});
  } catch (error) {
    return { success: false, retryLater: true, code: 0, error: 'Rangkaian gagal: ' + error };
  }
  if (res.code === 200) return { success: true, error: '' };
  return {
    success: false,
    code: res.code,
    error: describeEmailJsError_(res.code, res.text),
    retryLater: [403, 412, 426, 429].indexOf(res.code) >= 0 || res.code >= 500,
  };
}

/** Sama dengan EmailJsGateway.describeError. */
function describeEmailJsError_(status, body) {
  var detail = body.length > 200 ? body.substring(0, 200) + '…' : body;
  switch (status) {
    case 400:
      return 'EmailJS menolak permintaan (templat/ID salah): ' + detail;
    case 403:
      if (body.indexOf('strict mode') >= 0 || body.indexOf('Private Key') >= 0) {
        return 'EmailJS memerlukan private key (strict mode). Tampal private key ' +
          'di Admin tools → Email settings: ' + detail;
      }
      return 'EmailJS menyekat permintaan. Aktifkan "API for non-browser ' +
        'applications" atau semak Allowed origins: ' + detail;
    case 412:
      return 'Perkhidmatan emel EmailJS perlu disambung semula: ' + detail;
    case 426:
      return 'Kuota EmailJS telah habis. Naik taraf pelan EmailJS: ' + detail;
    case 429:
      return 'Terlalu banyak permintaan. Cuba semula sebentar lagi.';
    default:
      return 'EmailJS ralat ' + status + ': ' + detail;
  }
}

// ------------------------------------------------ tulisan Firestore (= email_service.dart)

function participantStatusWrite_(name, status) {
  return {
    update: { name: name, fields: { emailStatus: { stringValue: status } } },
    updateMask: { fieldPaths: ['emailStatus'] },
    updateTransforms: [{ fieldPath: 'emailUpdatedAt', setToServerValue: 'REQUEST_TIME' }],
    currentDocument: { exists: true },
  };
}

/** Log baharu – medan sama dengan EmailService._logMap. */
function newLogWrite_(message, status, error, studentUid, programId, attempts) {
  var id = newId_();
  var data = {
    id: id,
    recipient: message.to,
    subject: clip_(message.subject, 200),
    body: clip_(message.body, 3000),
    status: status,
    errorMessage: clip_(error, 1000),
    studentName: clip_(message.studentName, 120),
    studentUid: studentUid,
    programId: programId,
    programTitle: clip_(message.programTitle, 120),
    type: message.type,
    createdBy: CONFIG.logCreatedBy,
    attempts: attempts,
  };
  return {
    update: { name: docName_('email_logs/' + id), fields: toFields_(data) },
    updateTransforms: [
      { fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' },
      { fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' },
    ],
    currentDocument: { exists: false },
  };
}

/** Kemas kini log dalam barisan – sama dengan EmailService._deliver. */
function logUpdateWrite_(name, status, error, attempts) {
  return {
    update: {
      name: name,
      fields: toFields_({ status: status, errorMessage: clip_(error, 1000), attempts: attempts }),
    },
    updateMask: { fieldPaths: ['status', 'errorMessage', 'attempts'] },
    updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
    currentDocument: { exists: true },
  };
}

function newId_() {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  var id = '';
  for (var i = 0; i < 20; i++) id += chars.charAt(Math.floor(Math.random() * chars.length));
  return id;
}

// ================================================================ backup

function backupNow_() {
  var started = Date.now();
  var counts = {};
  var firestore = {};
  var skipped = [];

  // Had bacaan Spark 50k/hari: jika data terlalu besar, langkau log dahulu.
  var sizes = {};
  var total = 0;
  BACKUP_PARTS.forEach(function (part) {
    sizes[part.key] = countPart_(part);
    total += sizes[part.key];
  });
  BACKUP_PARTS.filter(function (p) { return p.optional; })
    .sort(function (a, b) { return a.optional - b.optional; })
    .forEach(function (part) {
      if (total > CONFIG.backupReadBudget) {
        skipped.push(part.key);
        total -= sizes[part.key];
      }
    });

  BACKUP_PARTS.forEach(function (part) {
    if (skipped.indexOf(part.key) >= 0) return;
    if (part.group) {
      var grouped = {};
      var n = 0;
      listGroup_(part.group).forEach(function (doc) {
        var segments = doc.name.split('/');
        var parentId = segments.length >= 4 ? segments[segments.length - 3] : '_';
        (grouped[parentId] = grouped[parentId] || {})[segments[segments.length - 1]] =
          fromFields_(doc.fields);
        n++;
      });
      firestore[part.key] = grouped;
      counts[part.key] = n;
    } else {
      var docs = {};
      listCollection_(part.collection, part.pageSize || 300).forEach(function (doc) {
        docs[doc.name.split('/').pop()] = fromFields_(doc.fields);
      });
      firestore[part.key] = docs;
      counts[part.key] = Object.keys(docs).length;
    }
  });

  // RTDB – sama dengan exportWorkspace(): tanpa settings (private key).
  var workspace = rtdb_('GET', 'admin_workspace') || {};
  delete workspace.settings;
  var rtdb = { admins: rtdb_('GET', 'admins'), admin_workspace: workspace };
  var other = {};
  Object.keys(rtdb_('GET', '', null, 'shallow=true') || {}).forEach(function (key) {
    if (key !== 'admins' && key !== 'admin_workspace') other[key] = rtdb_('GET', key);
  });

  var owner = ownerEmail_();
  var createdAt = new Date().toISOString();
  var stamp = createdAt.replace(/[:.]/g, '-').substring(0, 19);
  var fileName = 'myparentcare_backup_' + stamp + '.json';
  var payload = {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    createdAt: createdAt,
    createdBy: owner + ' (automatik)',
    counts: counts,
    firestore: firestore,
    rtdb: rtdb,
    rtdbOther: other,
    source: 'apps-script',
    skipped: skipped,
  };

  var folder = backupFolder_();
  var files = [];
  var json = JSON.stringify(payload);
  if (json.length > CONFIG.maxFileChars && firestore.media) {
    // Media (gambar) disimpan dalam fail berasingan supaya setiap fail < 50 MB.
    var mediaName = 'myparentcare_backup_' + stamp + '_media.json';
    var media = {
      format: BACKUP_FORMAT,
      version: BACKUP_VERSION,
      createdAt: createdAt,
      createdBy: payload.createdBy,
      counts: { media: counts.media },
      firestore: { media: firestore.media },
      source: 'apps-script',
    };
    delete firestore.media;
    delete counts.media;
    payload.mediaFile = mediaName;
    files.push(saveFile_(folder, mediaName, JSON.stringify(media)));
    json = JSON.stringify(payload);
  }
  files.unshift(saveFile_(folder, fileName, json));

  var documents = 0;
  Object.keys(counts).forEach(function (k) { documents += counts[k]; });
  if (payload.mediaFile) documents += media.counts.media;
  var bytes = files.reduce(function (sum, f) { return sum + f.size; }, 0);
  var note = 'Automatik → Google Drive/' + CONFIG.backupFolderName + '/' + fileName +
    (skipped.length ? ' (dilangkau: ' + skipped.join(', ') + ')' : '');
  rtdb_('POST', 'admin_workspace/backups', {
    at: { '.sv': 'timestamp' },
    by: CONFIG.logCreatedBy,
    byEmail: owner,
    documents: documents,
    bytes: bytes,
    kind: 'backup',
    note: clip_(note, 300),
  });

  var removed = pruneBackups_(folder, Date.now());
  if (skipped.length) {
    alert_('backup-budget', 'Backup automatik: sebahagian data dilangkau',
      'Data melebihi had bacaan ' + CONFIG.backupReadBudget + ' dokumen sehari, jadi ' +
      skipped.join(', ') + ' tidak dimasukkan. Buat backup penuh daripada aplikasi admin ' +
      'jika perlu, atau padam log emel lama.');
  }
  return {
    files: files.map(function (f) { return f.name; }),
    documents: documents,
    bytes: bytes,
    skipped: skipped,
    removedOld: removed,
    seconds: Math.round((Date.now() - started) / 1000),
  };
}

function countPart_(part) {
  var rows = fs_('POST', ':runAggregationQuery', {
    structuredAggregationQuery: {
      structuredQuery: {
        from: [part.group
          ? { collectionId: part.group, allDescendants: true }
          : { collectionId: part.collection }],
      },
      aggregations: [{ alias: 'n', count: {} }],
    },
  });
  var row = rows.filter(function (r) { return r.result; })[0];
  return row ? Number(row.result.aggregateFields.n.integerValue || 0) : 0;
}

function listCollection_(collection, pageSize) {
  var docs = [];
  var token = '';
  do {
    var page = fs_('GET', '/' + collection + '?pageSize=' + pageSize +
      (token ? '&pageToken=' + encodeURIComponent(token) : ''));
    docs = docs.concat(page.documents || []);
    token = page.nextPageToken || '';
  } while (token);
  return docs;
}

function listGroup_(collectionId) {
  var docs = [];
  var last = null;
  while (true) {
    var query = {
      from: [{ collectionId: collectionId, allDescendants: true }],
      orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
      limit: 300,
    };
    if (last) query.startAt = { values: [{ referenceValue: last }], before: false };
    var page = runQuery_(query);
    docs = docs.concat(page);
    if (page.length < 300) return docs;
    last = page[page.length - 1].name;
  }
}

function backupFolder_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('BACKUP_FOLDER_ID');
  if (id) {
    try {
      var saved = DriveApp.getFolderById(id);
      if (!saved.isTrashed()) return saved;
    } catch (ignored) {}
  }
  var found = DriveApp.getFoldersByName(CONFIG.backupFolderName);
  var folder = found.hasNext() ? found.next() : DriveApp.createFolder(CONFIG.backupFolderName);
  props.setProperty('BACKUP_FOLDER_ID', folder.getId());
  return folder;
}

function saveFile_(folder, name, content) {
  var file = folder.createFile(name, content, 'application/json');
  file.setDescription(BACKUP_DESCRIPTION);
  return { name: name, size: content.length };
}

/**
 * Simpan backup harian 30 hari, dan backup hari Isnin hingga 90 hari.
 * Hanya fail yang dicipta oleh skrip ini dibuang (ke Tong Sampah Drive).
 */
function pruneBackups_(folder, now) {
  var removed = 0;
  var files = folder.getFiles();
  while (files.hasNext()) {
    var file = files.next();
    if (file.getDescription() !== BACKUP_DESCRIPTION) continue;
    var created = file.getDateCreated().getTime();
    var ageDays = (now - created) / 86400000;
    var mondayInMalaysia = new Date(created + 8 * 3600000).getUTCDay() === 1;
    var keep = ageDays <= CONFIG.keepDailyDays ||
      (mondayInMalaysia && ageDays <= CONFIG.keepWeeklyDays);
    if (!keep) {
      file.setTrashed(true);
      removed++;
    }
  }
  return removed;
}

// ============================================================ Firestore REST

function docName_(path) {
  return 'projects/' + CONFIG.projectId + '/databases/(default)/documents/' + path;
}

function fs_(method, suffix, body) {
  var url = CONFIG.firestoreBase + '/projects/' + CONFIG.projectId +
    '/databases/(default)/documents' + suffix;
  var res = http_(method, url, body, {
    Authorization: 'Bearer ' + ScriptApp.getOAuthToken(),
    // Kuota dikira pada projek Firebase, bukan projek tersembunyi Apps Script.
    'x-goog-user-project': CONFIG.projectId,
  });
  if (res.code === 404 && method === 'GET') return null;
  if (res.code < 200 || res.code >= 300) {
    throw new Error('Firestore ' + method + ' ' + suffix.split('?')[0] + ' → ' + res.code +
      ': ' + res.text.slice(0, 300));
  }
  return res.text ? JSON.parse(res.text) : {};
}

function fsGet_(path) {
  return fs_('GET', '/' + path);
}

function fsGetByName_(name) {
  return fs_('GET', '/' + name.split('/documents/')[1]);
}

function runQuery_(structuredQuery) {
  return fs_('POST', ':runQuery', { structuredQuery: structuredQuery })
    .filter(function (row) { return row.document; })
    .map(function (row) { return row.document; });
}

function commit_(writes) {
  return fs_('POST', ':commit', { writes: writes });
}

function fieldEquals_(field, value) {
  return { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: value } } };
}

function str_(fields, key) {
  var v = fields && fields[key];
  return v && typeof v.stringValue === 'string' ? v.stringValue : '';
}

function tsMillis_(fields, key) {
  var v = fields && fields[key];
  return v && v.timestampValue ? Date.parse(v.timestampValue) : 0;
}

/** Nilai REST → JSON backup (= BackupService.encodeValue). */
function fromValue_(v) {
  if (!v || 'nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) {
    // Dart menerima hingga mikrosaat.
    return { __type: 'timestamp', value: v.timestampValue.replace(/\.(\d{6})\d+Z$/, '.$1Z') };
  }
  if ('bytesValue' in v) return { __type: 'bytes', value: v.bytesValue };
  if ('referenceValue' in v) return v.referenceValue;
  if ('geoPointValue' in v) {
    return { latitude: v.geoPointValue.latitude || 0, longitude: v.geoPointValue.longitude || 0 };
  }
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromValue_);
  if ('mapValue' in v) return fromFields_(v.mapValue.fields);
  return null;
}

function fromFields_(fields) {
  var out = {};
  Object.keys(fields || {}).forEach(function (k) { out[k] = fromValue_(fields[k]); });
  return out;
}

function toValue_(x) {
  if (x === null || x === undefined) return { nullValue: null };
  if (typeof x === 'boolean') return { booleanValue: x };
  if (typeof x === 'number') {
    return Number.isInteger(x) ? { integerValue: String(x) } : { doubleValue: x };
  }
  if (typeof x === 'string') return { stringValue: x };
  if (Array.isArray(x)) return { arrayValue: { values: x.map(toValue_) } };
  return { mapValue: { fields: toFields_(x) } };
}

function toFields_(data) {
  var fields = {};
  Object.keys(data).forEach(function (k) { fields[k] = toValue_(data[k]); });
  return fields;
}

// ================================================================== RTDB

function rtdb_(method, path, body, query) {
  var params = [CONFIG.rtdbQuery, query].filter(function (q) { return q; }).join('&');
  var url = CONFIG.rtdbUrl + '/' + path + '.json' + (params ? '?' + params : '');
  var res = http_(method, url, body, { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() });
  if (res.code < 200 || res.code >= 300) {
    throw new Error('RTDB ' + method + ' /' + path + ' → ' + res.code + ': ' + res.text.slice(0, 300));
  }
  return res.text ? JSON.parse(res.text) : null;
}

function readPrivateKey_() {
  var key = rtdb_('GET', 'admin_workspace/settings/emailjs/privateKey');
  if (typeof key === 'string' && key.trim()) return key.trim();
  var fallback = PropertiesService.getScriptProperties().getProperty('EMAILJS_PRIVATE_KEY');
  return fallback ? fallback.trim() : null;
}

function anyAdminOnline_() {
  var presence = rtdb_('GET', 'admin_workspace/presence') || {};
  return Object.keys(presence).some(function (uid) {
    return presence[uid] && presence[uid].online === true;
  });
}

// ================================================================ utiliti

function http_(method, url, body, headers) {
  var options = { method: method.toLowerCase(), muteHttpExceptions: true, headers: headers || {} };
  if (body !== undefined && body !== null) {
    options.contentType = 'application/json';
    options.payload = JSON.stringify(body);
  }
  var res = UrlFetchApp.fetch(url, options);
  return { code: res.getResponseCode(), text: res.getContentText() };
}

function ownerEmail_() {
  return Session.getEffectiveUser().getEmail() || 'pemilik skrip';
}

function errorText_(error) {
  return String((error && error.stack) || error).slice(0, 2000);
}

/** Amaran kepada pemilik (paling kerap sekali setiap 12 jam bagi setiap jenis). */
function alert_(kind, subject, body) {
  console.error(subject + ': ' + body);
  var props = PropertiesService.getScriptProperties();
  var key = 'ALERT_' + kind;
  var last = Number(props.getProperty(key) || 0);
  if (Date.now() - last < CONFIG.alertEveryHours * 3600000) return;
  props.setProperty(key, String(Date.now()));
  try {
    MailApp.sendEmail(CONFIG.alertEmail || ownerEmail_(), '[MyParentCare] ' + subject,
      body + '\n\n— Automasi MyParentCare (Google Apps Script)');
  } catch (error) {
    console.error('Emel amaran gagal: ' + error);
  }
}
