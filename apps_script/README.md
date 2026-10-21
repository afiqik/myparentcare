# Automasi MyParentCare (Google Apps Script) – percuma, kekal pelan Spark

Skrip ini berjalan di pelayan Google (bukan di telefon), jadi aplikasi admin **tidak perlu dibuka**.

| Fungsi | Bila | Apa yang berlaku |
| --- | --- | --- |
| Web app (`doPost`) | **serta-merta** selepas pelajar join | Aplikasi pelajar memanggil skrip ini. Emel pengesahan sampai kepada ibu bapa dalam beberapa saat. |
| `processEmails` | setiap 5 minit (sandaran) | Emel yang masih menunggu dihantar, contohnya jika telefon pelajar hilang internet. Emel kemas kini/pembatalan dalam barisan turut dihantar. |
| `dailyBackup` | setiap hari ~3 pagi | Backup penuh Firestore + RTDB disimpan dalam Google Drive → folder **MyParentCare Backups**. |

**EmailJS tidak diubah.** Skrip guna servis, templat, public key dan private key yang sama. Private key dibaca terus dari ruang kerja admin, iaitu yang ditampal di aplikasi admin → Tools → Email settings. Kunci itu tidak disalin ke skrip, tidak dicetak dalam log dan tidak dimasukkan dalam backup.

Kandungan emel sama dengan emel dari aplikasi. Ujian `test/unit/apps_script_compat_test.dart` dan `tests/firebase/apps_script` memastikan kedua-duanya kekal sepadan.

## Status pemasangan (production)

- Dipasang pada 2026-10-01 dengan akaun admin@myparentcare.com. Projek: **MyParentCare Automasi** (`scriptId` dalam [`.clasp.json`](.clasp.json)).
- Web app: `https://script.google.com/macros/s/AKfycbxIfTZ695gA2cOBtSSJ3aqH1hg1TmAwrS9UA-jOcIWJM5dibiEV4AtuTnNSWuvTrVIIhw/exec`. Pautan ini disimpan dalam Firestore `public/config`.
- Semakan: buka pautan web app dalam browser. Jawapan mesti `"ok":true`, `"keyConfigured":true` dan `"triggers":["dailyBackup","processEmails"]`.

Untuk kemas kini kod dari komputer ini, gunakan [clasp](https://github.com/google/clasp). Pautan web app kekal sama:

```bash
cd apps_script
npx @google/clasp@3.4.1 push --force
npx @google/clasp@3.4.1 update-deployment AKfycbxIfTZ695gA2cOBtSSJ3aqH1hg1TmAwrS9UA-jOcIWJM5dibiEV4AtuTnNSWuvTrVIIhw --description "MyParentCare emel"
```

## Pasang (sekali sahaja, ~5 minit)

1. Buka <https://script.google.com> dan log masuk dengan **admin@myparentcare.com**. Akaun ini mesti pemilik projek Firebase `myparentcare-45eb1`.
2. Tekan **New project**. Tukar nama projek kepada `MyParentCare Automasi`.
3. Tekan ⚙️ **Project Settings**. Tandakan **Show "appsscript.json" manifest file in editor**.
4. Kembali ke **Editor** (ikon `< >`):
   - Buka `appsscript.json`. Padam semua kandungan, kemudian tampal isi fail [`appsscript.json`](appsscript.json).
   - Buka `Code.gs`. Padam semua kandungan, kemudian tampal isi fail [`Code.gs`](Code.gs).
   - Tekan 💾 **Save** (Ctrl+S).
5. Pilih fungsi **`setup`** di menu atas, kemudian tekan ▶ **Run**.
   - Tetingkap kebenaran akan muncul. Tekan **Review permissions** dan pilih admin@myparentcare.com.
   - Jika keluar "Google hasn't verified this app", tekan **Advanced**, kemudian **Go to MyParentCare Automasi (unsafe)**. Amaran ini normal untuk skrip milik sendiri. Kemudian tekan **Allow**.
6. **Deploy sebagai web app** (untuk emel segera):
   - Tekan **Deploy** → **New deployment** → ⚙️ **Select type** → **Web app**.
   - Description: `MyParentCare emel`. **Execute as: Me (admin@myparentcare.com)**. **Who has access: Anyone**.
   - Tekan **Deploy**, kemudian salin **Web app URL** (berakhir `/exec`).
   - Jalankan **`setup`** sekali lagi. Skrip akan cuba menyimpan pautan secara automatik. Jika baris `Emel segera (web app)` masih `BELUM`, buka aplikasi admin → Tools → Email settings → **Web app URL**, tampal pautan, tekan **SAVE LINK** dan kemudian **Test**.
7. Lihat **Execution log**. Baris terakhir mesti **`SEMUA OK`**.
8. Ujian pilihan:
   - Jalankan `testEmail`. Satu emel ujian EmailJS akan masuk ke peti masuk admin@myparentcare.com (guna 1 daripada kuota 200/bulan).
   - Jalankan `dailyBackup`. Semak Google Drive → **MyParentCare Backups**. Kemudian semak aplikasi admin → Tools → Backup & restore: rekod **Automatic backup** akan dipaparkan.
9. Tekan ⏰ **Triggers** di sebelah kiri. Mesti ada 2 trigger: `processEmails` (5 minit) dan `dailyBackup` (harian).

Selepas itu anda tidak perlu buat apa-apa lagi. Jika ada masalah, skrip akan menghantar emel amaran ke admin@myparentcare.com (paling kerap sekali setiap 12 jam). Contoh masalah: private key tiada, kuota EmailJS habis, atau backup gagal.

> **Jika Code.gs dikemas kini kemudian:** Deploy → **Manage deployments** → ✏️ Edit → Version: **New version** → Deploy. Dengan cara ini pautan kekal sama. Jangan buat "New deployment" lagi kerana pautan akan berubah.

"Who has access: Anyone" diperlukan kerana aplikasi pelajar memanggil web app tanpa log masuk Google. Ia selamat kerana:

- Pemanggil hanya menghantar `programId` dan `uid`.
- Skrip membaca semula penyertaan itu dari Firestore. Ia hanya menghantar emel pengesahan yang memang masih menunggu, kepada emel ibu bapa yang tersimpan dalam profil.
- Skrip tidak menerima alamat emel atau kandungan daripada pemanggil.
- Permintaan dihadkan (300 seminit).

## Satu emel sahaja bagi setiap penyertaan

- Sebelum menghantar, setiap laluan (web app, trigger 5 minit, aplikasi admin) membaca semula status penyertaan. Jika status sudah `sent`, emel tidak dihantar lagi.
- Tuntutan sementara memastikan hanya satu laluan menghantar penyertaan yang sama pada satu masa.
- Aplikasi admin memberi web app 2 minit dahulu sebelum menghantar secara automatik. Butang manual **Send pending** tetap menghantar serta-merta.
- Emel kedua hanya dihantar jika pelajar keluar program dan join semula (itu penyertaan baharu).

## Jika emel gagal

| Keadaan | Status | Admin nampak | Pelajar nampak |
| --- | --- | --- | --- |
| Telefon pelajar hilang internet selepas join | `pending` | Banner "emails waiting" | Skrin join: *Sending…*. Emel dihantar oleh trigger ≤ 5 minit |
| Alamat emel ibu bapa ditolak EmailJS (400/422) | `failed` | Pusat Emel: log **failed** dengan sebab penuh dan butang **Retry**. Banner "emails failed" | Notifikasi **"Emel kepada ibu bapa gagal dihantar"** + petunjuk semak emel ibu bapa di Profil. Skrin join/Joined programs: *failed* |
| Masalah akaun EmailJS (private key salah, kuota habis 426, perkhidmatan 412) | kekal `pending`, dicuba semula automatik | Banner merah **"Automatic parent emails are paused: <sebab>"**. Tools → Email settings → *Automatic sending*. Emel amaran ke pemilik | Notifikasi **"Emel kepada ibu bapa tertangguh"** (sekali sahaja) |
| Ralat sementara (429, 5xx, rangkaian) | kekal `pending` | Seperti di atas jika berlarutan | Notifikasi tertangguh hanya jika menunggu > 15 minit |

Selepas masalah diselesaikan, emel yang menunggu dihantar secara automatik dan status admin kembali **Working normally**. Setiap notifikasi pelajar dihantar sekali sahaja bagi setiap penyertaan.

## Cara ia bekerjasama dengan aplikasi admin

- Jika admin sedang membuka aplikasi, trigger 5 minit hanya menghantar emel yang sudah menunggu lebih 3 minit.
- Jika EmailJS menolak kerana masalah akaun, emel **kekal menunggu** dan dicuba semula secara automatik selepas masalah diselesaikan. Masalah akaun termasuk private key salah, strict mode, kuota habis, terlalu banyak permintaan dan ralat pelayan.
- Emel yang ditolak kerana alamat atau templat salah ditanda `failed`, sama seperti aplikasi. Admin boleh cuba semula dari Pusat Emel.
- Log emel oleh skrip direkodkan dalam Pusat Emel dengan `createdBy = apps-script`.

## Backup

- Formatnya sama dengan backup dari aplikasi. Untuk memulihkan, super admin boleh buka Admin tools → Backup & restore → **Restore from file**, kemudian pilih fail dari Drive.
- Tempoh simpanan: backup harian disimpan 30 hari. Backup hari Isnin disimpan hingga 90 hari, selaras dengan Dasar Privasi. Fail lama dipindah ke Tong Sampah Drive. Hanya fail yang dicipta oleh skrip ini disentuh.
- Jika data melebihi 20,000 dokumen, notifikasi dan log emel dilangkau dan pemilik dimaklumkan. Tujuannya menjaga had bacaan Spark sebanyak 50,000 sehari.
- Jika fail melebihi ~45 MB, gambar (media) disimpan dalam fail `_media.json` berasingan. Fail ini juga boleh dipulihkan.
- Data lama RTDB (sebelum migrasi) disimpan di bawah `rtdbOther`.

## Had percuma (akaun Gmail)

| Perkara | Had | Penggunaan skrip |
| --- | --- | --- |
| Masa trigger Apps Script | 90 min/hari | ~10 min/hari (web app tidak dikira dalam had ini) |
| Web app serentak | 30 permintaan | Giliran EmailJS dikongsi; lebihan dihantar oleh trigger |
| UrlFetch | 20,000/hari | ~600 + 2 bagi setiap emel |
| Bacaan Firestore | 50,000/hari (Spark) | ~600/hari + satu kali jumlah dokumen untuk backup |
| EmailJS | 200 emel/bulan (pelan percuma) | tidak berubah |

## Masalah biasa

| Mesej dalam `checkSetup` | Penyelesaian |
| --- | --- |
| `Firestore: GAGAL – 403 ... SERVICE_DISABLED / has not been used in project` | Pergi ke Project Settings → **Google Cloud Platform (GCP) Project** → **Change project**. Masukkan *Project number* `myparentcare-45eb1` (Firebase console → Project settings), kemudian jalankan `setup` semula. |
| `403 PERMISSION_DENIED` | Anda log masuk dengan akaun yang bukan pemilik projek Firebase. Guna admin@myparentcare.com. |
| `Private key EmailJS: TIADA` | Tampal private key di aplikasi admin → Tools → Email settings. |
| `Emel segera (web app): BELUM` | Lakukan langkah 6 (Deploy → New deployment → Web app), kemudian jalankan `setup` atau tampal pautan di Email settings. |
| `Emel segera (web app): GAGAL – pautan tidak menjawab` | Semak Manage deployments: Execute as **Me**, Who has access **Anyone**. |

Untuk menghentikan automasi, jalankan `removeTriggers`.

## Ujian (pembangun)

```bash
export JAVA_HOME=~/.local/jdk-21 PATH=~/.local/jdk-21/bin:$PATH
firebase emulators:exec --project demo-myparentcare --only firestore,database \
  "cd tests/firebase && npm run test:apps-script"
flutter test test/unit/apps_script_compat_test.dart
```

Jika templat emel dalam aplikasi berubah, lakukan tiga langkah ini:

1. Jalankan `UPDATE_FIXTURES=1 flutter test test/unit/apps_script_compat_test.dart`.
2. Kemas kini `joinMessage_` dalam `Code.gs`.
3. Jalankan ujian Node semula.
