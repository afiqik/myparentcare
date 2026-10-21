# Ujian MyParentCare

Semua ujian guna pangkalan data **tiruan**: dalam memori atau Firebase Emulator di komputer. Pengecualian ialah ujian *smoke* production, yang **membaca sahaja**.

| Jenis | Fail | Bil. | Apa yang diuji |
| --- | --- | --- | --- |
| **Unit** | `test/unit/` | ~120 | Model data, repositori, AuthService (Google sahaja), StudentState/AdminState, emel & templat, backup/pulih, padam akaun, migrasi, mampatan gambar, eksport fail, Google Sign-In, laporan ralat, had kadar, backoff, sambungan, konfigurasi Firebase |
| **Widget** (setiap skrin) | `test/widget/` | ~85 | Setiap skrin admin & pelajar: borang, pengesahan medan, butang, menu, dialog, tapisan, carian, eksport CSV/PDF, backup/pulih, status emel, notifikasi, luar talian |
| **Interaksi penuh** | `test/flow/interaction_test.dart` | 2 | Dua "telefon" (admin + pelajar) dengan pangkalan data tiruan yang sama. Admin log masuk Google dan terbit program. Pelajar log masuk Google, setuju privasi, isi profil, join dan menerima emel segera. Admin melihat peserta dan membatalkan program. Pelajar mendapat notifikasi. Turut diuji laluan emel gagal. |
| **Pariti aplikasi ↔ Apps Script** | `test/unit/apps_script_compat_test.dart` | 3 | Emel dan backup daripada skrip sama dengan yang dihasilkan aplikasi |
| **Security Rules** (emulator) | `tests/firebase/rules/` | 71 | Pemisahan data ikut peranan: pelajar/admin/super admin, Firestore + RTDB |
| **Apps Script** (emulator) | `tests/firebase/apps_script/` | 31 | Emel segera (web app), trigger 5 minit, satu emel sahaja, sandaran & notifikasi bila gagal, backup harian, setup |
| **Beban** (emulator) | `tests/firebase/load/` | 1 | 2,000 pengguna, 400 join serentak, tiada lebihan tempat |
| **Smoke production** (baca sahaja) | `tests/firebase/smoke/` | 22 | Data dikunci daripada orang awam, laman muat turun, web app Apps Script aktif + private key + trigger, permintaan spam ditolak |

Liputan kod Dart: **90.8%** (`flutter test --coverage`). Bahagian yang tidak diliputi memerlukan telefon sebenar: sambungan RTDB (`RtdbAdminWorkspace`) dan permulaan Firebase dalam `main()`. Tingkah laku RTDB diuji melalui Security Rules di emulator.

## Cara menjalankan

```bash
# Unit + widget + interaksi + pariti
flutter test
flutter test --coverage            # laporan: coverage/lcov.info

# Emulator (perlu JDK 21)
export JAVA_HOME=~/.local/jdk-21 PATH=~/.local/jdk-21/bin:$PATH
firebase emulators:exec --project demo-myparentcare --only firestore,database \
  "cd tests/firebase && npm test"          # rules + Apps Script
firebase emulators:exec --project demo-myparentcare --only firestore \
  "cd tests/firebase && npm run load"      # ujian beban

# Production (baca sahaja)
cd tests/firebase && npm run smoke
```

## Nota untuk penulis ujian

- `test/support/widget_harness.dart`: `pumpScreen`, `settle`, `scrollTo`, `tapVisible`, `clearSnackBars`, `adminHarness`, `studentHarness`.
- `test/support/platform_fakes.dart`: plugin telefon tiruan untuk kongsi fail, pilih gambar/fail, Google Sign-In dan pelancar pautan.
- `test/flutter_test_config.dart` memuatkan fon sebenar (Manrope), supaya ujian limpahan (overflow) setepat telefon.
- `fake_cloud_firestore` tidak menstrim kemas kini *collection group* selepas snapshot awal. Sediakan data sebelum skrin dibuka, atau langgan semula.
- Cipta objek ujian di dalam `testWidgets`, bukan dalam `setUp`. Objek dalam `setUp` berjalan di luar jam ujian, jadi acara log masuk tidak sampai.
