// Persekitaran Google Apps Script tiruan untuk menguji apps_script/Code.gs
// terhadap Firebase Emulator. UrlFetchApp ialah HTTP sebenar (curl, segerak
// seperti Apps Script); EmailJS, Drive, Gmail dan trigger dirakam dalam memori.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
export const ROOT = resolve(here, '../../..');
export const EMAILJS_TEST_ENDPOINT = 'https://emailjs.test/api/v1.0/email/send';

function curl(url, options) {
  const method = (options.method || 'get').toUpperCase();
  const args = ['-sS', '-X', method, '-w', '\n@@STATUS@@%{http_code}'];
  for (const [name, value] of Object.entries(options.headers || {})) {
    args.push('-H', `${name}: ${value}`);
  }
  if (options.payload !== undefined) {
    args.push('-H', `Content-Type: ${options.contentType || 'application/json'}`);
    args.push('--data-binary', '@-');
  }
  args.push(url);
  const out = execFileSync('curl', args, {
    input: options.payload ?? '',
    maxBuffer: 512 * 1024 * 1024,
  }).toString('utf8');
  const at = out.lastIndexOf('\n@@STATUS@@');
  return { code: Number(out.slice(at + 11)), text: out.slice(0, at) };
}

function iterator(items) {
  let i = 0;
  return { hasNext: () => i < items.length, next: () => items[i++] };
}

/**
 * Muatkan Code.gs dalam konteks VM baharu. `config` menimpa CONFIG (contoh:
 * alamat emulator). Pulangkan { gas, state } – gas = fungsi global skrip.
 */
export function loadScript({ projectId, config = {} } = {}) {
  const state = {
    emails: [],
    emailResponder: () => ({ code: 200, text: 'OK' }),
    mails: [],
    props: new Map(),
    triggers: [],
    folders: [],
    sleeps: [],
    lockBusy: false,
    requests: [],
    cache: new Map(),
    webAppUrl: null,
    webAppDown: false,
  };
  let seq = 0;

  class DriveFile {
    constructor(name, content, mimeType) {
      this.id = `file${++seq}`;
      this.name = name;
      this.content = content;
      this.mimeType = mimeType;
      this.created = new Date();
      this.trashed = false;
      this.description = null;
    }
    getId() { return this.id; }
    getName() { return this.name; }
    getDateCreated() { return this.created; }
    getDescription() { return this.description; }
    setDescription(text) { this.description = text; return this; }
    isTrashed() { return this.trashed; }
    setTrashed(value) { this.trashed = value; return this; }
  }

  class DriveFolder {
    constructor(name) {
      this.id = `folder${++seq}`;
      this.name = name;
      this.files = [];
      this.trashed = false;
    }
    getId() { return this.id; }
    getName() { return this.name; }
    isTrashed() { return this.trashed; }
    createFile(name, content, mimeType) {
      const file = new DriveFile(name, content, mimeType);
      this.files.push(file);
      return file;
    }
    getFiles() { return iterator(this.files.filter((f) => !f.trashed)); }
  }
  state.DriveFile = DriveFile;

  const response = ({ code, text }) => ({
    getResponseCode: () => code,
    getContentText: () => text,
  });

  const globals = {
    console: { log() {}, error() {}, warn() {}, info() {} },
    UrlFetchApp: {
      fetch(url, options = {}) {
        if (state.webAppUrl && url === state.webAppUrl) {
          if (state.webAppDown) return response({ code: 404, text: 'Not Found' });
          const out = (options.method || 'get').toLowerCase() === 'post'
            ? context.doPost({ postData: { contents: options.payload } })
            : context.doGet({});
          return response({ code: 200, text: out.getContent() });
        }
        if (url === EMAILJS_TEST_ENDPOINT) {
          const payload = JSON.parse(options.payload);
          state.emails.push(payload);
          return response(state.emailResponder(payload, state.emails.length));
        }
        state.requests.push(`${(options.method || 'get').toUpperCase()} ${url.split('?')[0]}`);
        return response(curl(url, options));
      },
    },
    ScriptApp: {
      getOAuthToken: () => 'owner',
      getService: () => ({ getUrl: () => state.webAppUrl }),
      getProjectTriggers: () => [...state.triggers],
      deleteTrigger(trigger) {
        state.triggers = state.triggers.filter((t) => t !== trigger);
      },
      newTrigger(handler) {
        const schedule = {};
        const builder = {
          timeBased: () => builder,
          everyMinutes: (n) => { schedule.everyMinutes = n; return builder; },
          everyDays: (n) => { schedule.everyDays = n; return builder; },
          atHour: (h) => { schedule.atHour = h; return builder; },
          create: () => {
            const trigger = { getHandlerFunction: () => handler, schedule };
            state.triggers.push(trigger);
            return trigger;
          },
        };
        return builder;
      },
    },
    CacheService: {
      getScriptCache: () => ({
        get(key) {
          const entry = state.cache.get(key);
          if (!entry || entry.expires < Date.now()) return null;
          return entry.value;
        },
        put(key, value, seconds = 600) {
          state.cache.set(key, { value: String(value), expires: Date.now() + seconds * 1000 });
        },
        remove(key) { state.cache.delete(key); },
      }),
    },
    ContentService: {
      MimeType: { JSON: 'application/json' },
      createTextOutput(text) {
        return {
          mimeType: null,
          setMimeType(type) { this.mimeType = type; return this; },
          getContent: () => text,
        };
      },
    },
    LockService: {
      getScriptLock: () => ({ tryLock: () => !state.lockBusy, releaseLock() {} }),
    },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: (key) => (state.props.has(key) ? state.props.get(key) : null),
        setProperty(key, value) { state.props.set(key, String(value)); return this; },
      }),
    },
    Utilities: {
      sleep: (ms) => state.sleeps.push(ms),
      formatDate: (date) => date.toISOString().slice(0, 16).replace('T', ' '),
    },
    Session: { getEffectiveUser: () => ({ getEmail: () => 'owner@kptm.test' }) },
    MailApp: {
      sendEmail: (to, subject, body) => state.mails.push({ to, subject, body }),
    },
    DriveApp: {
      getFolderById(id) {
        const folder = state.folders.find((f) => f.id === id);
        if (!folder) throw new Error(`No item with the given ID could be found: ${id}`);
        return folder;
      },
      getFoldersByName: (name) =>
        iterator(state.folders.filter((f) => f.name === name && !f.trashed)),
      createFolder(name) {
        const folder = new DriveFolder(name);
        state.folders.push(folder);
        return folder;
      },
    },
  };

  const context = vm.createContext(globals);
  vm.runInContext(readFileSync(resolve(ROOT, 'apps_script/Code.gs'), 'utf8'), context, {
    filename: 'Code.gs',
  });

  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8181';
  const databaseHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9001';
  Object.assign(context.CONFIG, {
    projectId,
    firestoreBase: `http://${firestoreHost}/v1`,
    rtdbUrl: `http://${databaseHost}`,
    rtdbQuery: `ns=${projectId}`,
    ...config,
  });
  context.CONFIG.emailJs.endpoint = EMAILJS_TEST_ENDPOINT;
  return { gas: context, state };
}

/** Panggil web app seperti aplikasi pelajar (doPost) dan pulangkan JSON. */
export function post(gas, body) {
  const out = gas.doPost({ postData: { contents: JSON.stringify(body) } });
  assertJson(out);
  return JSON.parse(out.getContent());
}

function assertJson(out) {
  if (out.mimeType !== 'application/json') throw new Error(`web app mesti pulangkan JSON, bukan ${out.mimeType}`);
}

/** Salinan biasa (realm Node) supaya deepStrictEqual boleh membandingkan. */
export const plain = (value) => JSON.parse(JSON.stringify(value));
