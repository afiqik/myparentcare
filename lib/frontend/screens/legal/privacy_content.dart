// FAIL DIJANA oleh tool/generate_legal.py – jangan ubah secara manual.

class LegalSection {
  final String title;
  final List<String> paragraphs;

  const LegalSection(this.title, this.paragraphs);
}

class PrivacyContent {
  PrivacyContent._();

  static const version = "2026-09-30";
  static const title = "Dasar Privasi MyParentCare";
  static const intro = "Dasar ini menerangkan bagaimana MyParentCare mengumpul, menggunakan, menyimpan dan melindungi data peribadi anda selaras dengan Akta Perlindungan Data Peribadi 2010 (Malaysia). Berkuat kuasa: 2026-09-30.";

  static const sections = <LegalSection>[
    LegalSection("1. Siapa kami", [
      "MyParentCare ialah aplikasi pendaftaran program khas untuk pelajar KPTM Batu Pahat yang memaklumkan ibu bapa atau penjaga melalui emel. Pengawal data: Pasukan Pembangun MyParentCare. Hubungi kami di admin@myparentcare.com.",
    ]),
    LegalSection("2. Data yang kami kumpul", [
      "Maklumat akaun Google: nama dan alamat emel akaun Google anda. Log masuk hanya melalui Google – kami tidak menerima atau menyimpan kata laluan anda.",
      "Maklumat pelajar: nombor matrik, kursus, semester dan nombor telefon.",
      "Maklumat ibu bapa/penjaga: nama, alamat emel, nombor telefon dan hubungan.",
      "Aktiviti dalam aplikasi: program yang disertai, tarikh penyertaan, notifikasi dan status penghantaran emel kepada ibu bapa.",
      "Data teknikal: laporan ralat aplikasi (mesej ralat, jenis peranti/platform, versi aplikasi dan ID pengguna) untuk membaiki masalah. Kami tidak mengumpul lokasi, kenalan, gambar peribadi atau data pengiklanan.",
    ]),
    LegalSection("3. Tujuan penggunaan", [
      "Mendaftar dan mengurus akaun anda serta penyertaan program.",
      "Menghantar emel pengesahan, kemas kini dan pembatalan program kepada ibu bapa/penjaga yang anda namakan.",
      "Membolehkan pentadbir program menyediakan senarai peserta dan laporan.",
      "Keselamatan (mencegah penyalahgunaan) dan membaiki ralat aplikasi.",
      "Kami TIDAK menjual data anda, tidak menggunakan data untuk pengiklanan dan tidak berkongsi data dengan pihak ketiga untuk tujuan pemasaran.",
    ]),
    LegalSection("4. Persetujuan dan data ibu bapa", [
      "Dengan mendaftar, anda bersetuju dengan pemprosesan data seperti yang diterangkan di sini.",
      "Anda mengesahkan bahawa anda mendapat kebenaran ibu bapa/penjaga untuk memberikan maklumat hubungan mereka bagi tujuan notifikasi program.",
      "Pelajar di bawah 18 tahun hendaklah menggunakan aplikasi ini dengan pengetahuan dan kebenaran ibu bapa/penjaga.",
    ]),
    LegalSection("5. Siapa yang boleh melihat data anda", [
      "Anda: profil, penyertaan dan notifikasi anda sendiri sahaja. Pelajar lain tidak boleh melihat data anda.",
      "Pentadbir program (admin) yang dilantik: maklumat peserta program, log emel dan laporan. Setiap tindakan admin direkodkan dalam log audit.",
      "Pemproses data: Google Firebase (Authentication, Cloud Firestore, Realtime Database) untuk menyimpan data, dan EmailJS untuk menghantar emel kepada ibu bapa (menerima emel ibu bapa, nama pelajar dan butiran program).",
      "Pihak berkuasa jika dikehendaki oleh undang-undang.",
    ]),
    LegalSection("6. Lokasi penyimpanan", [
      "Data disimpan pada pelayan Google Cloud (Firebase), termasuk di Singapura dan Amerika Syarikat. Google melindungi data dengan penyulitan semasa penghantaran dan penyimpanan.",
    ]),
    LegalSection("7. Tempoh penyimpanan", [
      "Data akaun dan penyertaan disimpan selagi akaun anda aktif.",
      "Log penghantaran emel disimpan sehingga 12 bulan, kemudian dipadam oleh admin.",
      "Laporan ralat teknikal disimpan sehingga 90 hari.",
      "Salinan sandaran (backup) dibuat secara automatik setiap hari dan disimpan secara selamat dalam Google Drive akaun pasukan pembangun (akses terhad) untuk maksimum 90 hari.",
    ]),
    LegalSection("8. Padam akaun dan data", [
      "Dalam aplikasi: Profil → Padam akaun. Semua data anda (profil, maklumat ibu bapa, penyertaan, notifikasi dan log emel berkaitan) dipadam serta-merta dan akaun log masuk anda dipadam.",
      "Tanpa aplikasi: layari https://website-81b96.web.app/delete-account atau emel admin@myparentcare.com daripada alamat emel akaun anda. Permintaan diproses dalam masa 30 hari.",
      "Data dalam salinan sandaran akan hilang apabila sandaran tersebut tamat tempoh (maksimum 90 hari). Rekod tanpa nama bahawa sebuah akaun telah dipadam disimpan untuk laporan.",
    ]),
    LegalSection("9. Hak anda", [
      "Mengakses dan membetulkan data anda pada bila-bila masa melalui skrin Profil.",
      "Menarik balik persetujuan dengan memadam akaun anda.",
      "Membuat pertanyaan atau aduan kepada kami di admin@myparentcare.com, atau kepada Jabatan Perlindungan Data Peribadi (JPDP) Malaysia.",
    ]),
    LegalSection("10. Keselamatan", [
      "Sambungan disulitkan (HTTPS/TLS). Akses data dikawal oleh peraturan keselamatan berasaskan peranan – setiap pelajar hanya boleh mengakses data sendiri, dan data admin disimpan dalam pangkalan data yang berasingan.",
      "Walaupun kami mengambil langkah munasabah, tiada sistem yang 100% selamat. Sila gunakan kata laluan yang kukuh dan jangan berkongsi akaun.",
    ]),
    LegalSection("11. Perubahan dasar", [
      "Jika dasar ini dikemas kini, tarikh berkuat kuasa akan ditukar dan aplikasi akan meminta persetujuan anda semula sebelum anda meneruskan.",
    ]),
  ];

  static const englishSummary = <String>[
    "MyParentCare is a program registration app for KPTM Batu Pahat students. It collects your account details, student details and your parent/guardian's contact details to register you for programs and email your parent/guardian about them.",
    "Data is stored with Google Firebase and parent emails are sent through EmailJS. We do not sell data or use it for advertising.",
    "Only you and appointed program administrators can see your data; every admin action is audit-logged.",
    "Delete your account any time in the app (Profile → Delete account), at https://website-81b96.web.app/delete-account, or by emailing admin@myparentcare.com.",
  ];

  static const deletedData = <String>[
    "Profil pelajar (nama, emel, nombor matrik, kursus, semester, telefon).",
    "Maklumat ibu bapa/penjaga (nama, emel, telefon, hubungan).",
    "Semua penyertaan program (tempat anda dilepaskan semula), notifikasi dan log emel ibu bapa berkaitan.",
    "Akaun log masuk Firebase Authentication anda.",
  ];

  static const keptAfterDeletion = <String>[
    "Rekod tanpa nama bahawa sebuah akaun telah dipadam (tarikh dan sebab pilihan) – tiada data peribadi.",
    "Salinan sandaran (backup) sedia ada akan tamat tempoh dalam masa maksimum 90 hari.",
  ];
}
