// Hantar SATU emel ujian SEBENAR melalui EmailJS, sama seperti aplikasi Android.
//
//   cd tests/firebase && npm run email:test -- penerima@contoh.com
//
// Konfigurasi dibaca terus daripada lib/app_config.dart. Akaun EmailJS dalam
// strict mode memerlukan private key: berikan melalui EMAILJS_PRIVATE_KEY
// (contoh: dibaca daripada ruang kerja admin RTDB) – JANGAN tulis dalam fail.
// Permintaan dihantar tanpa pelayar (seperti aplikasi Android), jadi ia turut
// menguji tetapan EmailJS "Allow EmailJS API for non-browser applications".

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const config = readFileSync(resolve(root, 'lib/app_config.dart'), 'utf8');
const read = (name) => config.match(new RegExp(`${name} =\\s*'([^']*)'`))?.[1] ?? '';

const to = process.argv[2];
if (!to || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) {
  console.error('Guna: npm run email:test -- penerima@contoh.com');
  process.exit(2);
}

const serviceId = read('emailJsServiceId');
const templateId = read('emailJsTemplateId');
const publicKey = read('emailJsPublicKey');
const endpoint = read('emailJsEndpoint');
const sentAt = new Date().toISOString().slice(0, 16).replace('T', ' ');

const privateKey = (process.env.EMAILJS_PRIVATE_KEY ?? '').trim();
const payload = {
  service_id: serviceId,
  template_id: templateId,
  user_id: publicKey,
  ...(privateKey ? { accessToken: privateKey } : {}),
  template_params: {
    to_email: to,
    subject: `MyParentCare: Emel ujian (${sentAt} UTC)`,
    message: [
      'Salam sejahtera,',
      '',
      'Ini ialah emel ujian daripada MyParentCare.',
      'Jika anda menerima emel ini, penghantaran emel kepada ibu bapa berfungsi dengan betul.',
      '',
      `Masa: ${sentAt} UTC`,
    ].join('\n'),
    student_name: 'Ujian Sistem',
    program_title: 'Emel ujian MyParentCare',
    program_date: '',
    program_time: '',
    program_location: '',
    reason: '',
    type: 'test',
  },
};

console.log(`EmailJS service=${serviceId} template=${templateId} → ${to} (private key: ${privateKey ? 'ya' : 'tiada'})`);

const started = Date.now();
const res = await fetch(endpoint, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(payload),
});
const body = (await res.text()).slice(0, 300);
console.log(`HTTP ${res.status} dalam ${Date.now() - started} ms: ${body}`);

const hints = {
  400: 'ID servis/templat salah atau templat tidak menggunakan {{to_email}} sebagai penerima.',
  403: 'Strict mode: tampal private key di aplikasi (Admin tools → Email settings), atau aktifkan "Allow EmailJS API for non-browser applications".',
  412: 'Sambung semula perkhidmatan Gmail di EmailJS → Email Services.',
  426: 'Kuota EmailJS habis – naik taraf pelan.',
  429: 'Terlalu banyak permintaan – cuba lagi sebentar.',
};
if (res.status === 200) {
  console.log('✔ EmailJS menerima emel. Semak peti masuk (dan folder Spam).');
} else {
  console.log(`✖ Gagal. ${hints[res.status] ?? ''}`);
  process.exit(1);
}
