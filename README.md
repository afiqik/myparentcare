# MyParentCare

Aplikasi pendaftaran program **khas untuk pelajar KPTM Batu Pahat**. Pelajar
menyertai program dengan satu pengesahan, dan ibu bapa/penjaga menerima
butirannya melalui emel secara automatik.

* Aplikasi **Android** sahaja. Laman muat turun: https://website-81b96.web.app
* Firebase (pelan Spark): Authentication, Cloud Firestore, Realtime Database
* Dasar Privasi: https://website-81b96.web.app/privacy
* Padam akaun: https://website-81b96.web.app/delete-account

## Ciri utama

**Pelajar** – daftar (persetujuan privasi + pengesahan emel), profil & maklumat
ibu bapa, katalog program dengan gambar & video, sertai program (tempat dijamin,
tiada overbooking), program disertai, notifikasi & pengumuman, padam akaun.

**Admin** – papan pemuka langsung, cipta/sunting program dengan media, buka/
tutup/selesai/arkib/batal (notifikasi + emel ibu bapa), senarai peserta & CSV,
Pusat Emel (barisan, cuba semula, emel tertangguh), laporan CSV/PDF, pengguna &
peranan (gantung, lantik admin), pengumuman, log audit, backup & pulih, laporan
ralat, migrasi data versi lama.

## Struktur kod

```
lib/
  api/                   EmailJS (public key sahaja), templat emel, eksport fail
  auth/                  AuthService, Google Sign-In
  availability/          status sambungan
  backend_logic/         StudentState, AdminState, emel, backup, padam akaun, migrasi
  cache_cdn/             cache Firestore/RTDB, cache media LRU, pemampat gambar
  database_storage/      model, repositori Firestore, ruang kerja admin RTDB
  error_tracking/        laporan ralat (Firestore, berhad kuota)
  load_balancer_scaling/ shard kaunter tempat, backoff + jitter
  rate_limiting/         pengehad kadar klien
  security/              pengesahan input
  frontend/              skrin & widget
firestore.rules          Security Rules Firestore (diuji: tests/firebase/rules)
database.rules.json      Security Rules RTDB (ruang kerja admin)
tests/firebase/          ujian rules, ujian beban, ujian Apps Script, ujian request production
apps_script/             automasi percuma: emel ibu bapa segera + sandaran 5 minit + backup harian ke Drive
website/                 laman muat turun statik (Firebase project website-81b96)
tool/generate_legal.py   jana laman muat turun, Dasar Privasi & Padam Akaun (app + laman)
scripts/                 jana kunci upload Play Store
docs/PRODUCTION_SETUP.md panduan penuh production & Play Store
```

## Mula

```bash
flutter pub get
flutter run                 # Android
flutter test                # 207 ujian (lihat docs/TESTING.md)
```

Pindah ke laptop lain / penyelenggaraan: **[docs/HANDOVER.md](docs/HANDOVER.md)** (ciri, entry point, endpoint, lokasi fail).

Lihat **[docs/PRODUCTION_SETUP.md](docs/PRODUCTION_SETUP.md)** untuk deploy,
ujian emulator, EmailJS, SHA-1 (Google Sign-In Error 10) dan senarai semak Play Store.
