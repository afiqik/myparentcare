# MyParentCare – Panduan Production (Pelan Spark / percuma)

Aplikasi khas untuk pelajar **KPTM Batu Pahat**. Dokumen ini menerangkan seni
bina, keselamatan, ujian dan langkah terbitan ke Google Play.

---

## 1. Seni bina (3 servis Firebase sahaja)

| Servis | Kegunaan | Siapa boleh akses |
|---|---|---|
| **Authentication** | **Google Sign-In sahaja** (pelajar & admin). Tiada kata laluan. Profil pelajar wajib dilengkapkan sebelum sertai program | – |
| **Cloud Firestore** | Data pelajar & awam: profil, katalog program, penyertaan, notifikasi, log emel, gambar program | Pelajar: data sendiri + katalog. Admin: semua |
| **Realtime Database** | **Ruang kerja admin sahaja**: log audit (tidak boleh diubah), admin dalam talian, sejarah backup, senarai admin | Admin sahaja. Pelajar langsung tidak boleh membaca |

Kenapa dipisahkan begini?
* Pelan Spark mengehadkan RTDB kepada **100 sambungan serentak**. Pelajar hanya
  menggunakan Firestore, jadi 2,000 pelajar tidak akan mencapai had itu.
* Data admin berada dalam pangkalan data yang **berasingan secara fizikal**
  daripada data pelajar ("database asing antara role").

### Struktur Firestore
```
users/{uid}                              profil (pemilik + admin)
users/{uid}/notifications/{id}           notifikasi pelajar
public/catalog                           SEMUA program awam + pengumuman (1 bacaan)
programs/{id}                            data penuh program termasuk draf (admin)
programs/{id}/participants/{uid}         penyertaan (pemilik + admin)
program_seats/{id}/shards/{s00..}        kaunter tempat bershard {count, cap}
media/{id}                               gambar (Blob < 900 KB) / pautan video
email_logs/{id}                          log emel ibu bapa (admin)
error_reports/{id}                       laporan ralat aplikasi (admin)
account_deletions/{id}                   rekod tanpa nama akaun dipadam
```

### Skala untuk 2,000 pengguna (percuma)
* **Katalog 1 dokumen** – pelajar membuka aplikasi dengan ~5 bacaan sahaja
  (profil, katalog, penyertaan sendiri). 1,000 pelajar aktif sehari ≈ 10k
  bacaan/hari (had percuma: 50k).
* **Kaunter tempat bershard** – kapasiti dipecah ~10 tempat setiap shard
  (maks 50). Ujian beban: **400 pelajar tekan Join serentak** → 150/150 tempat
  diisi, 0 overbooking, 0 ralat.
* **Cache**: cache luar talian Firestore 100 MB, cache memori LRU untuk gambar,
  dokumen media tidak berubah (dimuat turun sekali setiap peranti).
* **Backoff + jitter** apabila berlaku pertembungan (lihat
  `lib/load_balancer_scaling/`). "Load balancing" pelayan diurus oleh Google.

### Gambar & video (tanpa Cloud Storage)
* Gambar dimampatkan dalam aplikasi (maks 1600 px, < 900 KB) dan disimpan
  sebagai Blob dalam Firestore.
* Video: muat naik ke YouTube (Unlisted) atau Google Drive, kemudian tampal
  pautan dalam borang program. Firestore tidak boleh menyimpan fail > 1 MiB.

---

## 2. Keselamatan

* **Security Rules** (`firestore.rules`, `database.rules.json`) ialah "pelayan"
  aplikasi ini. Ia menguatkuasakan peranan, kapasiti, satu tempat seorang,
  pengesahan emel, penggantungan akaun dan pemisahan data.
* **Tiada akaun demo / kata laluan tertanam.** Kod auto-cipta admin telah dibuang.
* **Google sahaja**: rules menolak penciptaan profil jika `sign_in_provider` bukan
  `google.com`. Disyorkan juga: Firebase Console → Authentication → Sign-in
  method → **matikan Email/Password** (hanya Google dihidupkan).
* **Profil wajib**: pengguna baharu → persetujuan privasi → "Set up your profile"
  (tiada butang kembali). Rules juga menolak penyertaan jika profil/ibu bapa tidak lengkap.
* **Super admin**: `admin@myparentcare.com` (emel mesti disahkan – log masuk
  dengan Google). Senarai ini ada di 3 tempat yang MESTI sama:
  `lib/app_config.dart`, `firestore.rules`, `database.rules.json`.
  Hanya super admin boleh melantik/melucutkan admin dan memulihkan backup.
* **Log audit** setiap tindakan admin (RTDB, append-only).
* **EmailJS**: private key telah DIBUANG daripada aplikasi. Lihat §5.

---

## 3. Ujian

Panduan penuh semua jenis ujian: **[docs/TESTING.md](TESTING.md)**.

```bash
# Ujian Flutter (unit + widget + interaksi + pariti): 207 lulus, 1 dilangkau – liputan 90.8%
flutter test

# Ujian Security Rules + ujian beban (perlu JDK 21)
export JAVA_HOME=~/.local/jdk-21 PATH=~/.local/jdk-21/bin:$PATH
firebase emulators:exec --project demo-myparentcare --only firestore,database \
  "cd tests/firebase && npm test"          # 102 ujian: 71 rules + 31 Apps Script
firebase emulators:exec --project demo-myparentcare --only firestore \
  "cd tests/firebase && npm run load"      # 2000 pengguna, 400 join serentak

# Ujian request ke production (selepas deploy)
cd tests/firebase && npm run smoke          # baca sahaja: 22 semakan (rules, laman, Apps Script)
cd tests/firebase && npm run smoke:write    # + semakan tulis (selepas rules deploy)
```

---

## 4. Deploy

Aplikasi ini **hanya untuk Android** – tiada versi web aplikasi.

```bash
# Rules & indeks (projek myparentcare-45eb1)
firebase deploy --only firestore:rules,firestore:indexes,database

# Laman muat turun (projek website-81b96): https://website-81b96.web.app
python3 tool/generate_legal.py            # selepas menukar APK_URL/versi/checksum
cd website && firebase deploy --only hosting

# myparentcare-45eb1.web.app hanya redirect ke laman muat turun
firebase deploy --only hosting            # dari folder projek (hosting-redirect/)
```

APK ujian diedarkan melalui Google Drive. Setiap APK baharu: muat naik ke Drive
("Anyone with the link"), kemas kini `APK_URL`, `APK_BUILD`, `APK_SIZE_MB` dan
`APK_SHA256` dalam `tool/generate_legal.py`, jana semula dan deploy `website/`.

Selepas deploy pertama:
1. Log masuk di aplikasi Android sebagai **Administrator** dengan
   Google menggunakan `admin@myparentcare.com` → akaun admin dicipta secara automatik.
2. Admin tools → System health → **Find & import old data** (pindah data lama
   daripada RTDB terbuka) → semak → **Delete old data**.
3. Padam akaun demo lama dalam Firebase Console → Authentication:
   `admin@myparentcare.com` dan `student@myparentcare.com` (kata laluannya pernah
   didedahkan dalam APK lama).
4. Pasang automasi percuma **[apps_script/README.md](../apps_script/README.md)**:
   emel ibu bapa automatik (setiap 5 minit) + backup harian ke Google Drive.
   Backup manual masih boleh dibuat: Admin tools → Backup & restore → **Create backup**.

---

## 5. EmailJS (strict mode – private key di ruang kerja admin)

Akaun EmailJS kekal dalam **strict mode** ("Use Private Key" ON). Oleh itu public
key dalam APK tidak boleh disalahgunakan tanpa private key.

* **Private key TIDAK dalam APK/git.** Admin menampalnya dalam aplikasi:
  **Admin tools → Email settings → SAVE KEY**. Ia disimpan di
  `admin_workspace/settings/emailjs` (RTDB, admin sahaja; dikecualikan daripada backup).
* Pelajar tidak menghantar emel. Selepas pelajar sertai, emel ibu bapa berstatus
  *pending* dan telefon pelajar serta-merta memanggil **web app Google Apps
  Script** – emel sampai kepada ibu bapa dalam beberapa saat
  ([apps_script/README.md](../apps_script/README.md)). Sandaran: trigger skrip
  setiap 5 minit dan aplikasi admin (selepas 2 minit, atau Pusat Emel → Pending
  confirmations). Semua guna EmailJS, templat dan private key yang sama, dan
  setiap laluan menyemak status dahulu supaya ibu bapa menerima satu emel sahaja.
* Emel gagal: admin melihat sebab (Pusat Emel / banner status automasi) dan
  pelajar menerima notifikasi dalam aplikasi.
* EmailJS → Account → Security: "Use Private Key" **ON**, "Allow EmailJS API for
  non-browser applications" **ON**.
* Kunci dalam tangkapan skrin 2026-09-30 ialah kunci lama yang pernah bocor
  dalam APK v1. Disyorkan: **Refresh Keys** di EmailJS, kemudian tampal kunci
  baharu di Email settings.
* Pelan percuma EmailJS = **200 emel/bulan** – naik taraf untuk 2,000 pelajar.

Uji penghantaran sebenar:
* Dalam aplikasi: Admin tools → Email settings → **Send test email**.
* Skrip (kunci dibaca daripada RTDB, tidak ditulis ke fail):
  ```bash
  cd tests/firebase
  EMAILJS_PRIVATE_KEY="$(firebase database:get /admin_workspace/settings/emailjs/privateKey --project myparentcare-45eb1 | tr -d '"')" \
    npm run email:test -- admin@myparentcare.com
  ```

---

## 6. Google Sign-In "Error 10" (SHA-1)

Error 10 = cap jari SHA-1 aplikasi yang dipasang tidak didaftarkan dalam Firebase.
Setiap kunci yang menandatangani APK memerlukan SHA-1 **dan** SHA-256 sendiri:

| Kunci | Bila digunakan | Status |
|---|---|---|
| Debug (komputer ini) | `flutter run` | ✔ Didaftarkan |
| **Upload key** (`~/myparentcare-keys/upload-keystore.jks`) | APK/AAB release, ujian tester | ✔ Didaftarkan |
| **Play App Signing key** | Aplikasi yang dimuat turun dari Play Store | **Anda tambah** selepas muat naik AAB pertama |

Langkah untuk Play App Signing (selepas muat naik AAB pertama):
1. Play Console → aplikasi → **Test and release → App integrity → App signing**.
2. Salin **SHA-1** dan **SHA-256** "App signing key certificate".
3. Jalankan (atau tambah di Firebase Console → Project settings → Android app):
   ```bash
   firebase apps:android:sha:create 1:177388431094:android:e0dcee0071201889ab6ed7 <SHA1>
   firebase apps:android:sha:create 1:177388431094:android:e0dcee0071201889ab6ed7 <SHA256>
   ```
4. Muat turun semula `google-services.json` ke `android/app/`, build semula.

**Backup kunci upload**: salin `~/myparentcare-keys/upload-keystore.jks` dan
`android/key.properties` ke tempat selamat. JANGAN commit ke git.

---

## 7. Senarai semak Google Play

- [ ] Akaun Play Console (peribadi baharu: **ujian tertutup 12 penguji × 14 hari**
      sebelum production)
- [ ] `flutter build appbundle --release` → muat naik `app-release.aab`
- [ ] Nama: **MyParentCare**; penerangan menyebut "untuk pelajar KPTM Batu Pahat"
- [ ] Privacy policy URL: `https://website-81b96.web.app/privacy`
- [ ] Account deletion URL: `https://website-81b96.web.app/delete-account`
- [ ] Data safety: Nama, Emel, Telefon, ID pengguna (nombor matrik), maklumat
      ibu bapa; tujuan: fungsi aplikasi & komunikasi; disulitkan semasa
      penghantaran; pengguna boleh meminta pemadaman; tidak dikongsi untuk iklan
- [ ] App access: beri akaun ujian pelajar (BUKAN admin) kepada reviewer Google
- [ ] Target audience: 18+ (atau 16+ dengan kebenaran ibu bapa – ikut polisi KPTM)
- [ ] Ikon 512×512, feature graphic 1024×500, sekurang-kurangnya 2 screenshot
- [ ] **Nama KPTM**: jika aplikasi ini bukan aplikasi rasmi KPTM, dapatkan
      kebenaran bertulis atau nyatakan "Aplikasi tidak rasmi" dalam penerangan
      – polisi Play melarang aplikasi yang mengelirukan tentang gabungan dengan
      organisasi.

---

## 8. Had pelan Spark & bila perlu naik taraf

| Had | Nilai | Bila tercapai |
|---|---|---|
| Firestore bacaan | 50,000/hari | ~5,000 pelajar aktif sehari |
| Firestore tulisan | 20,000/hari | ~6,000 pendaftaran sehari |
| RTDB sambungan | 100 serentak | Hanya admin – tidak dicapai |
| Hosting (laman muat turun) | 360 MB/hari | Tidak dicapai – APK dimuat turun dari Google Drive |
| EmailJS percuma | 200/bulan | **Dicapai dahulu** – naik taraf EmailJS |

Emel automatik dari pelayan dan backup harian sudah disediakan secara percuma
melalui Google Apps Script. Naik taraf ke Blaze (bayar ikut guna) masih memberi
Cloud Functions (pencetus segera), Cloud Storage (video sebenar) dan backup
terurus Firestore (PITR).
