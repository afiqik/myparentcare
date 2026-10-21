# MyParentCare – Nota Serah Tugas & Penyelenggaraan

Nota ini untuk sesiapa yang menyambung projek di **laptop lain**, sama ada untuk membaiki, menaik taraf atau menyelenggara. Baca bahagian 1–4 dahulu sebelum mengubah apa-apa.

> Ringkasnya: aplikasi Flutter (Android) ini guna **Firebase pelan percuma (Spark)**: Auth (Google), Firestore dan Realtime Database. Emel ibu bapa dihantar melalui **EmailJS**. Automasi pelayan percuma (emel segera, sandaran 5 minit, backup harian) berjalan di **Google Apps Script**. APK diedarkan melalui **Google Drive** dan **laman muat turun** (Firebase Hosting).

---

## 1. Gambaran sistem

```
 Telefon PELAJAR (APK)                    Telefon ADMIN (APK yang sama)
  │ log masuk Google                        │ log masuk Google (emel admin)
  ▼                                         ▼
 Firebase Auth ──────────── projek myparentcare-45eb1 ────────────┐
  │                                                               │
  ├─► Cloud Firestore  (data pelajar & awam: profil, program,     │
  │                     penyertaan, notifikasi, log emel, media)  │
  │                                                               │
  └─► Realtime Database (RUANG KERJA ADMIN SAHAJA: senarai admin, ◄┘
                         log audit, kehadiran, rekod backup,
                         private key EmailJS, status automasi)

 Selepas pelajar JOIN ─► Google Apps Script (web app, akaun owner)
                          ├─ baca penyertaan (Firestore) + private key (RTDB)
                          ├─ hantar emel ─► EmailJS ─► Gmail ibu bapa
                          ├─ trigger 5 minit: hantar emel yang masih menunggu
                          └─ trigger harian 3 pagi: backup ─► Google Drive
```

Prinsip keselamatan:
- **Pelajar tidak pernah menyambung ke RTDB.**
- **Private key EmailJS tidak ada dalam APK atau git.** Ia hanya disimpan di RTDB `admin_workspace/settings/emailjs`.
- Akses data ikut peranan dikuatkuasakan oleh `firestore.rules` dan `database.rules.json`. Kedua-duanya ada 71 ujian.

---

## 2. Akaun & akses yang diperlukan

| Perkara | Akaun / lokasi | Kegunaan |
| --- | --- | --- |
| Firebase projek **myparentcare-45eb1** | admin@myparentcare.com (pemilik) | Auth, Firestore, RTDB, Hosting (redirect) |
| Firebase projek **website-81b96** | admin@myparentcare.com | Laman muat turun / Dasar Privasi / Padam Akaun |
| Google Apps Script **MyParentCare Automasi** | admin@myparentcare.com | Emel segera, sandaran 5 minit, backup harian |
| Google Drive | Akaun yang memegang fail APK | Pautan muat turun APK |
| Google Drive → folder **MyParentCare Backups** | admin@myparentcare.com | Backup harian automatik |
| EmailJS | Akaun EmailJS pemilik | Servis `service_aeph2e8`, templat `template_pbwdb3p` |
| Super admin aplikasi | `admin@myparentcare.com` (`AppConfig.superAdminEmails`) | Melantik admin lain, memulihkan backup |

---

## 3. Fail RAHSIA (tiada dalam git) – mesti dipindahkan secara selamat

| Fail | Lokasi di laptop lama | Kenapa penting |
| --- | --- | --- |
| `upload-keystore.jks` | `~/myparentcare-keys/upload-keystore.jks` | Menandatangani APK/AAB. **Jika hilang, kemas kini aplikasi untuk pengguna sedia ada tidak boleh dipasang di atas versi lama**, dan Play Store menolak AAB. Simpan 2 salinan (contoh: pemacu USB dan storan awan peribadi yang disulitkan). |
| `android/key.properties` | dalam projek (di-*gitignore*) | Kata laluan & laluan keystore untuk `flutter build`. |
| `psw.md` | dalam projek (di-*gitignore*) | Nota kelayakan peribadi. Jangan kongsi atau commit. |

Pindahkan ketiga-tiga fail ini melalui medium peribadi, **bukan** emel atau chat awam.

Fail ini **tidak perlu** dipindahkan:
- Private key EmailJS. Ia ada di RTDB, jadi tidak dipindah.
- `~/.clasprc.json` dan login Firebase CLI. Log masuk semula di laptop baharu.

`android/app/google-services.json` **ada dalam git**. Ia konfigurasi awam, bukan rahsia. Fail `google-services (1).json` di akar projek ialah salinan muat turun lama yang tidak digunakan.

---

## 4. Sediakan laptop baharu

```bash
# 1) Salin projek (folder penuh) ATAU git clone dari repo peribadi anda
cd ~/Downloads/MyParentCare/MyParentCare

# 2) Alat
#    Flutter 3.44.9 (stable)  – https://docs.flutter.dev/get-started/install
#    Android Studio + Android SDK (build-tools, platform 36)
#    Node.js 22  – untuk ujian Firebase & Apps Script
#    JDK 21      – untuk Firebase Emulator (letak di ~/.local/jdk-21 atau tetapkan JAVA_HOME)
npm install -g firebase-tools

# 3) Kebergantungan projek
flutter pub get
(cd tests/firebase && npm ci)

# 4) Log masuk (guna admin@myparentcare.com)
firebase login
npx @google/clasp@3.4.1 login        # untuk kemas kini Apps Script (tanda "Select all")

# 5) Fail rahsia (bahagian 3)
mkdir -p ~/myparentcare-keys && cp <salinan>/upload-keystore.jks ~/myparentcare-keys/
cp <salinan>/key.properties android/key.properties

# 6) Pastikan semua berfungsi
flutter analyze && flutter test
```

Untuk **Google Sign-In dalam mod debug** di laptop baharu, daftar SHA-1 keystore debug laptop itu dalam Firebase Console → Project settings → Android app:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA1
```

APK *release* tidak terjejas kerana ia guna keystore upload yang sama. SHA-1 keystore upload sudah didaftarkan: `2c:6d:b8:27:…:98:25`.

---

## 5. Peta folder & fail

| Folder / fail | Isi |
| --- | --- |
| `lib/main.dart` | **Titik mula aplikasi.** `main()` memulakan Firebase. `AppServices.create()` mencipta semua servis. `MyParentCareApp` menyediakan Provider: `AuthService`, `StudentState`, `AdminState`, `ConnectivityManager`. |
| `lib/app_config.dart` | **Semua konfigurasi**: nama aplikasi, institusi, emel sokongan, super admin, URL laman, URL RTDB, client ID Google, ID EmailJS, had gambar. |
| `lib/firebase_options.dart` | Konfigurasi Firebase (dijana oleh FlutterFire). Android/iOS → `myparentcare-45eb1`. |
| `lib/auth/` | `auth_service.dart`: log masuk Google, peringkat akaun (`AuthStage`), profil, persetujuan privasi, akses admin, padam akaun. `google_auth_adapter.dart`: plugin google_sign_in. |
| `lib/backend_logic/` | Logik utama. `student_state.dart` (pelajar), `admin_state.dart` (semua tindakan admin + audit), `email_service.dart` (log & barisan emel), `backup_service.dart`, `account_deletion_service.dart`, `legacy_migration_service.dart`. |
| `lib/database_storage/` | Akses data. `firestore_paths.dart` (nama koleksi), `models.dart` (semua model), `program_repository.dart` (program, join, tempat, notifikasi, katalog), `user_repository.dart`, `media_repository.dart` (gambar Blob & pautan video), `admin_workspace.dart` (RTDB ruang kerja admin). |
| `lib/api/` | Luar aplikasi. `email_gateway.dart` (EmailJS), `email_templates.dart` (kandungan emel), `email_relay.dart` (panggil web app Apps Script), `file_export*.dart` (kongsi CSV/PDF/JSON). |
| `lib/load_balancer_scaling/` | `seat_planner.dart` (kaunter tempat berpecah, *sharded*), `retry_policy.dart` (cubaan semula + jitter). |
| `lib/cache_cdn/` | Cache Firestore 100 MB, mampatan gambar, cache media. |
| `lib/security/input_validator.dart` | Pengesahan medan borang. |
| `lib/rate_limiting/`, `lib/availability/`, `lib/error_tracking/`, `lib/core/errors.dart` | Had kadar, status luar talian, laporan ralat ke Firestore, mesej ralat mesra pengguna. |
| `lib/frontend/navigation.dart` | `homeForAuth()` menentukan skrin pertama ikut keadaan akaun. |
| `lib/frontend/screens/auth/` | Splash, onboarding, log masuk (Welcome), persetujuan, digantung. |
| `lib/frontend/screens/student/` | Semua skrin pelajar. |
| `lib/frontend/screens/admin/` | Semua skrin admin. |
| `lib/frontend/screens/legal/` | Dasar Privasi (`privacy_content.dart` **dijana**, jangan sunting tangan). |
| `lib/frontend/widgets/`, `theme.dart` | Komponen UI kongsi (`app_components.dart`, `media_widgets.dart`, `app_shell.dart`) & tema (fon Manrope). |
| `firestore.rules`, `database.rules.json`, `firestore.indexes.json` | Security Rules & indeks (deploy ke production). |
| `apps_script/` | `Code.gs` (automasi), `appsscript.json` (skop & web app), `.clasp.json` (ID skrip), `README.md`. |
| `website/` | Laman muat turun (Firebase projek `website-81b96`). `public/` dijana oleh `tool/generate_legal.py`. |
| `hosting-redirect/` | `myparentcare-45eb1.web.app` → 301 ke laman muat turun. |
| `tool/generate_legal.py` | **Satu sumber** Dasar Privasi (aplikasi + laman) dan maklumat APK di laman (pautan Drive, versi, saiz, SHA-256). |
| `scripts/create_upload_keystore.sh` | Cipta keystore upload baharu. Hanya jika keystore benar-benar hilang. |
| `test/` | Ujian Flutter: `unit/`, `widget/`, `flow/` (interaksi penuh), `support/` (harness & tiruan), `fixtures/`. |
| `tests/firebase/` | Ujian Node: `rules/` (Security Rules), `apps_script/`, `load/` (beban), `smoke/` (production, baca sahaja), `email/` (emel ujian EmailJS). |
| `docs/` | `PRODUCTION_SETUP.md` (deploy & Play Store), `TESTING.md` (semua jenis ujian), nota ini. |

---

## 6. Ciri-ciri: titik masuk (entry point) → logik → data → endpoint

### Pelajar

| Ciri | Skrin (entry point) | Logik | Data / endpoint |
| --- | --- | --- | --- |
| Buka aplikasi & penghalaan | `auth/splash_screen.dart` → `navigation.dart:homeForAuth()` | `AuthService.stage` | Firebase Auth, `users/{uid}` |
| Pengenalan kali pertama | `auth/onboarding_screen.dart` | SharedPreferences `onboarding_done` | – |
| Log masuk Google | `auth/welcome_screen.dart` (butang `google_sign_in`) | `AuthService.signInWithGoogle()` → `DefaultGoogleAuthAdapter` | Google Sign-In (client `AppConfig.googleServerClientId`) → Firebase Auth |
| Persetujuan Dasar Privasi | `auth/consent_screen.dart` | `AuthService.createMissingProfile()` / `acceptPrivacyPolicy()` | `users/{uid}.privacyVersion` = `AppConfig.privacyPolicyVersion` |
| Profil wajib & ibu bapa | `student/complete_profile_screen.dart` | `AuthService.updateProfile()` | `users/{uid}` |
| Utama | `student/student_dashboard.dart` (dalam `student_nav_layout.dart`) | `StudentState.attach()` | `public/catalog` (1 bacaan) |
| Senarai / cari / tapis program | `student/program_list_screen.dart` | `StudentState.programs` | `public/catalog` |
| Butiran program, gambar & video | `student/program_detail_screen.dart`, `widgets/media_widgets.dart` | `StudentState.refreshSeats()` | `program_seats/{pid}/shards/*`, `media/{id}`, pautan YouTube/Drive (url_launcher) |
| **Join program** | `student/join_confirmation_screen.dart` → `join_success_screen.dart` | `StudentState.joinProgram()` → `ProgramRepository.joinProgram()` (transaksi + shard) | `programs/{pid}/participants/{uid}` + `program_seats/.../shards` |
| **Emel segera kepada ibu bapa** | (automatik selepas join) | `StudentState._notifyParent()` → `EmailRelay.notifyJoin()` | `public/config.emailRelayUrl` → **web app Apps Script** → EmailJS |
| Program saya (Upcoming / Completed / Cancelled) | `student/joined_programs_screen.dart` | `ProgramRepository.watchMyParticipations()` | collection group `participants` |
| Notifikasi & pengumuman | `student/notifications_screen.dart` (loceng di bar atas) | `StudentState.loadNotifications()` / `markNotificationRead()` | `users/{uid}/notifications`, `public/catalog.announcements` |
| Profil | `student/profile_screen.dart` | – | `users/{uid}` |
| Padam akaun | `student/delete_account_screen.dart` | `AuthService.deleteAccount()` → `AccountDeletionService` | padam profil, penyertaan, notifikasi, log; rekod `account_deletions` |
| Luar talian | `widgets/app_shell.dart` | `ConnectivityManager` (tenang 4 saat) | – |

### Admin

Admin guna APK yang sama. `homeForAuth()` menghantar admin ke `admin/admin_nav_layout.dart`, yang mengandungi 5 tab: Overview, Programs, Email, Reports, Tools.

| Ciri | Skrin (entry point) | Logik (`AdminState`) | Data / endpoint |
| --- | --- | --- | --- |
| Sahkan akses admin | `admin_nav_layout.dart` | `AuthService.ensureAdminAccess()` → `AdminState.attach()` | RTDB `admins/{uid}`, `admin_workspace/presence` |
| Papan pemuka & amaran | `admin_dashboard.dart` | `refreshDashboard()`, `emailAutomation`, `backupOverdue` | Firestore kiraan, RTDB `automation/email`, `backups` |
| Senarai program | `admin_programs_screen.dart` | `programs` | `programs` |
| Cipta / edit program, gambar, video | `create_program_screen.dart` | `createProgram()`, `updateProgram()`, `uploadImage()`, `addVideoLink()` | `programs`, `program_seats`, `media`, `public/catalog` |
| Buka/tutup/selesai/arkib/batal/padam/salin | `program_detail_admin.dart` (menu "Program actions") | `setProgramStatus()`, `cancelProgram()`, `deleteProgram()`, `duplicateProgram()` | `programs`, notifikasi pelajar, emel dalam barisan |
| Peserta: cari, tapis, CSV, hantar semula, buang | `participant_list_screen.dart` | `resendParticipantEmail()`, `removeParticipant()` | `programs/{pid}/participants` |
| Pusat Emel | `email_logs_screen.dart` | `processEmailQueue()`, `sendPendingJoinEmails()`, `retryEmail()`, `clearEmailLogs()`, `sendTestEmail()` | `email_logs`, EmailJS |
| Tetapan emel (private key, web app, status automasi) | `email_settings_screen.dart` (Tools → Email settings) | `saveEmailJsPrivateKey()`, `saveEmailRelayUrl()`, `testEmailRelay()` | RTDB `admin_workspace/settings/emailjs`, Firestore `public/config` |
| Laporan CSV/PDF | `reports_screen.dart` | `email.fetchLogs()` | – |
| Pengguna & peranan | `admin_users_screen.dart` | `listUsers()`, `findUserByEmail()`, `setUserStatus()`, `setUserRole()` | `users`, RTDB `admins` |
| Pengumuman | `announcements_screen.dart` | `addAnnouncement()`, `deleteAnnouncement()` | `public/catalog.announcements` |
| Backup & pulih | `backup_screen.dart` | `createBackup()`, `restoreBackup()` (super admin) | fail JSON (kongsi), RTDB `backups` |
| Log audit | `audit_log_screen.dart` | `audit` | RTDB `admin_workspace/audit_logs` (append-only) |
| Kesihatan sistem & migrasi data lama | `system_screen.dart` | `migrateLegacy()`, `deleteLegacyData()` | `error_reports`, nod lama RTDB |

### Automasi (Google Apps Script – `apps_script/Code.gs`)

| Fungsi | Dicetuskan oleh | Apa berlaku |
| --- | --- | --- |
| `doPost` → `sendJoinNow_` | Aplikasi pelajar selepas join | Baca penyertaan, kemudian hantar 1 emel melalui EmailJS. Tandakan `sent`/`failed` dan tulis `email_logs`. |
| `doGet` | Semakan kesihatan (pelayar / smoke test) | Pulangkan `{ok, service, version, keyConfigured, triggers}` |
| `processEmails` | Trigger setiap 5 minit | Hantar penyertaan `pending` dan emel `queued`. Bila gagal, maklumkan pelajar dan tulis status admin. |
| `dailyBackup` | Trigger harian ~3 pagi | Backup Firestore + RTDB ke Drive "MyParentCare Backups". Simpanan: harian 30 hari, Isnin 90 hari. |
| `setup` / `checkSetup` / `testEmail` / `removeTriggers` | Dijalankan manual di editor | Pasang trigger, semak sambungan, hantar emel ujian, hentikan automasi |

Mekanisme "satu emel sahaja": `claim_()` (kunci sementara) dan baca semula status sebelum hantar. Aplikasi admin pula memberi web app 2 minit dahulu (`AdminState.instantEmailGrace`).

---

## 7. Endpoint & konfigurasi

| Perkara | Nilai | Ditetapkan di |
| --- | --- | --- |
| Firebase projek aplikasi | `myparentcare-45eb1` | `lib/firebase_options.dart`, `android/app/google-services.json`, `.firebaserc` |
| Realtime Database | `https://myparentcare-45eb1-default-rtdb.asia-southeast1.firebasedatabase.app` | `AppConfig.rtdbUrl`, `apps_script/Code.gs CONFIG.rtdbUrl` |
| Firestore REST (Apps Script) | `https://firestore.googleapis.com/v1/projects/myparentcare-45eb1/databases/(default)/documents` | `Code.gs CONFIG` |
| Google Sign-In (server client) | `177388431094-pjn60qqln9mt3c156ra9c370dbdqctat.apps.googleusercontent.com` | `AppConfig.googleServerClientId` |
| Package Android | `com.myparentcare.my_parent_care` | `android/app/build.gradle.kts` |
| Web app Apps Script | `https://script.google.com/macros/s/AKfycbxIfTZ695gA2cOBtSSJ3aqH1hg1TmAwrS9UA-jOcIWJM5dibiEV4AtuTnNSWuvTrVIIhw/exec` | Firestore `public/config.emailRelayUrl` (dibaca aplikasi), `tests/firebase/smoke`, `apps_script/README.md` |
| ID skrip Apps Script | `1DmJd_op99Kkh204eTJjRm3AyEUY79NX4i2KChMPUFwxBf7ZtUBHoUHIz` | `apps_script/.clasp.json` |
| EmailJS | `https://api.emailjs.com/api/v1.0/email/send` · servis `service_aeph2e8` · templat `template_pbwdb3p` · public key `nIq9l3JATYQyg179z` | `AppConfig`, `Code.gs CONFIG.emailJs` |
| EmailJS private key | (rahsia) RTDB `admin_workspace/settings/emailjs/privateKey` | Aplikasi admin → Tools → Email settings |
| Laman muat turun | `https://website-81b96.web.app` (`/privacy`, `/delete-account`, `/#muat-turun`) | `AppConfig.websiteUrl`, `website/` |
| Pautan APK (Drive) | `APK_URL` dalam `tool/generate_legal.py` | dijana ke `website/public/index.html` |

Templat EmailJS mesti mempunyai pemboleh ubah berikut: `{{to_email}} {{subject}} {{message}} {{student_name}} {{program_title}} {{program_date}} {{program_time}} {{program_location}} {{reason}} {{type}}`.

---

## 8. Model data

**Firestore** (projek `myparentcare-45eb1`):

| Laluan | Kandungan | Siapa boleh baca / tulis |
| --- | --- | --- |
| `users/{uid}` | profil pelajar/admin, maklumat ibu bapa, `role`, `status`, `privacyVersion`, `unreadNotifications` | pemilik & admin |
| `users/{uid}/notifications/{id}` | notifikasi dalam aplikasi | pemilik baca/tanda dibaca; admin cipta |
| `public/catalog` | semua program terbuka + 20 pengumuman (1 dokumen, jimat bacaan) | semua yang log masuk baca; admin tulis |
| `public/config` | `emailRelayUrl` (web app Apps Script) | semua yang log masuk baca; admin tulis |
| `programs/{pid}` | data penuh program (termasuk draf) | admin |
| `programs/{pid}/participants/{uid}` | penyertaan + salinan maklumat ibu bapa + `emailStatus` | pelajar cipta sendiri (transaksi), admin semua |
| `program_seats/{pid}/shards/{sNN}` | kaunter tempat `{count, cap}` | dikemas kini dalam transaksi join |
| `media/{id}` | gambar (Blob ≤ 900 KB) / pautan video | semua baca; admin tulis |
| `email_logs/{id}` | log setiap emel (`sent/failed/queued`, sebab ralat) | admin; pelajar lihat log sendiri |
| `error_reports/{id}` | laporan ralat aplikasi | cipta oleh pengguna; admin baca |
| `account_deletions/{id}` | rekod tanpa nama akaun dipadam | admin |

**Realtime Database** (admin sahaja): `admins/{uid}`, `admin_workspace/{audit_logs, presence, backups, notes, settings/emailjs, automation/email}`. Nod lama sebelum migrasi (`users`, `programs`, `participants`, …) dikunci untuk admin.

---

## 9. Tugas penyelenggaraan biasa

### Keluarkan APK baharu
1. Naikkan `version:` dalam `pubspec.yaml`. Nombor selepas `+` mesti lebih besar, contoh `1.0.0+8`.
2. Jalankan `flutter analyze && flutter test` (lihat `docs/TESTING.md`).
3. Bina APK:
   ```bash
   flutter build apk --release --target-platform android-arm64
   ```
   Hasilnya di `build/app/outputs/flutter-apk/app-release.apk`.
4. Sahkan tandatangan. SHA-1 mesti `2c:6d:b8:27:…`:
   ```bash
   ~/Android/Sdk/build-tools/<versi>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
   ```
5. Muat naik APK ke Drive dan tetapkan "Anyone with the link".
6. Kemas kini `APK_URL`, `APK_BUILD`, `APK_SIZE_MB` dan `APK_SHA256` dalam `tool/generate_legal.py`. Kemudian jalankan:
   ```bash
   python3 tool/generate_legal.py
   cd website && firebase deploy --only hosting --project website-81b96
   ```
7. Untuk Play Store, bina AAB dengan `flutter build appbundle --release`. Lihat `docs/PRODUCTION_SETUP.md` bahagian 7.

### Ubah Security Rules / indeks
Sunting `firestore.rules` / `database.rules.json`, kemudian tambah ujian dalam `tests/firebase/rules/`, kemudian:
```bash
firebase emulators:exec --project demo-myparentcare --only firestore,database "cd tests/firebase && npm test"
firebase deploy --only firestore:rules,firestore:indexes,database --project myparentcare-45eb1
```

### Kemas kini Apps Script
Sunting `apps_script/Code.gs`, kemudian jalankan `npm run test:apps-script` di emulator, kemudian:
```bash
cd apps_script
npx @google/clasp@3.4.1 push --force
npx @google/clasp@3.4.1 update-deployment AKfycbxIfTZ695gA2cOBtSSJ3aqH1hg1TmAwrS9UA-jOcIWJM5dibiEV4AtuTnNSWuvTrVIIhw --description "MyParentCare emel"
```
Guna `update-deployment` supaya pautan web app kekal sama. **Jangan** buat deployment baharu.

### Tukar templat emel ibu bapa
Templat ditakrifkan di dua tempat dan mesti sepadan:
- **Aplikasi:** `lib/api/email_templates.dart`
- **Skrip:** `apps_script/Code.gs` (`joinMessage_`)

Langkah:
1. Ubah kedua-dua tempat.
2. Jalankan `UPDATE_FIXTURES=1 flutter test test/unit/apps_script_compat_test.dart`.
3. Jalankan ujian Apps Script. Ia akan gagal jika skrip tidak sepadan dengan aplikasi.

### Lain-lain
- **Tukar private key EmailJS** (contoh: selepas "Refresh Keys" di EmailJS): aplikasi admin → Tools → Email settings → SAVE KEY. Skrip terus guna kunci baharu.
- **Tambah admin**: super admin → Tools → Users & roles → pelajar → **Make admin**.
- **Pulihkan backup**: super admin → Tools → Backup & restore → Restore from file, kemudian pilih fail JSON dari Drive "MyParentCare Backups".
- **Ubah Dasar Privasi**: sunting `tool/generate_legal.py` dan jalankannya. Jika perubahan besar, naikkan `AppConfig.privacyPolicyVersion` supaya pengguna diminta setuju semula. Kemudian deploy laman.
- **Tambah medan profil**: ubah `models.dart` (AppUser), `complete_profile_screen.dart`, `firestore.rules` (`profileKeys`/`validProfile`) dan ujian rules + unit.

---

## 10. Ujian (wajib sebelum keluaran)

Lihat **[docs/TESTING.md](TESTING.md)**. Ringkasan keputusan semasa:
- Flutter: 207 lulus (liputan 90.8%).
- Emulator: 102 lulus (71 rules + 31 Apps Script).
- Ujian beban: 5/5 semakan lulus.
- Smoke production: 22/22 lulus.

Untuk menyemak production selepas deploy (baca sahaja):

```bash
cd tests/firebase && npm run smoke
```

---

## 11. Masalah biasa

| Gejala | Punca & penyelesaian |
| --- | --- |
| Google Sign-In "error 10" | SHA-1 keystore tidak didaftarkan dalam Firebase. Tambah SHA-1, muat turun semula `google-services.json`, kemudian bina semula. |
| Emel tidak dihantar, banner merah "paused" | Lihat Tools → Email settings → *Automatic sending*. 403 bermaksud private key salah/tiada. 426 bermaksud kuota EmailJS (200/bulan) habis. |
| Emel lambat, bukan segera | `public/config.emailRelayUrl` tiada/salah. Semak pautan di Email settings → Test. |
| `checkSetup` Apps Script: Firestore 403 SERVICE_DISABLED | Ikut `apps_script/README.md`: tukar projek GCP skrip kepada nombor projek `myparentcare-45eb1`. |
| Build release gagal "key.properties" | Fail rahsia belum disalin (bahagian 3). |
| Gradle kehabisan memori | `org.gradle.jvmargs` dalam `android/gradle.properties` (kini 4G), dan bina arm64 sahaja. |
| Emulator gagal mula | Perlu JDK 21. Port 8080 mungkin digunakan, jadi port emulator ditetapkan dalam `firebase.json` (Firestore 8181, RTDB 9001, Auth 9199). |

---

## 12. Had & risiko yang diketahui

- **Pelan Spark**: 50k bacaan / 20k tulisan Firestore sehari, 100 sambungan RTDB serentak (admin sahaja). EmailJS percuma: **200 emel sebulan**. Naik taraf EmailJS jika pelajar ramai.
- Data versi lama dalam RTDB belum dimigrasi. Gunakan Tools → System health → Find & import old data.
- iOS belum disediakan untuk keluaran.
- Commit asas awal (`d097f94`) mengandungi rahsia lama. **Jangan push repo ini ke tempat awam.**
- Ujian automatik guna pangkalan data tiruan dan emulator. Selepas setiap keluaran, buat juga ujian manual ringkas di telefon sebenar: log masuk, join satu program, dan pastikan emel ibu bapa sampai.
