#!/usr/bin/env python3
"""Jana Dasar Privasi & halaman Padam Akaun daripada SATU sumber.

Output:
  lib/frontend/screens/legal/privacy_content.dart  (paparan dalam aplikasi)
  web/privacy.html                                  (URL untuk Google Play)
  web/delete-account.html                           (URL padam akaun Google Play)

Jalankan semula setiap kali kandungan diubah:  python3 tool/generate_legal.py
Kemudian tukar AppConfig.privacyPolicyVersion supaya pengguna bersetuju semula.
"""
import html
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

VERSION = "2026-09-30"
APP = "MyParentCare"
CONTACT = "admin@myparentcare.com"
CONTROLLER = "Pasukan Pembangun MyParentCare"
INSTITUTION = "KPTM Batu Pahat"
WEB = "https://website-81b96.web.app"

PRIVACY_TITLE = "Dasar Privasi MyParentCare"
PRIVACY_INTRO = (
    f"Dasar ini menerangkan bagaimana {APP} mengumpul, menggunakan, menyimpan dan "
    "melindungi data peribadi anda selaras dengan Akta Perlindungan Data Peribadi 2010 "
    f"(Malaysia). Berkuat kuasa: {VERSION}."
)

PRIVACY_SECTIONS = [
    ("1. Siapa kami", [
        f"{APP} ialah aplikasi pendaftaran program khas untuk pelajar {INSTITUTION} yang "
        f"memaklumkan ibu bapa atau penjaga melalui emel. Pengawal data: {CONTROLLER}. "
        f"Hubungi kami di {CONTACT}.",
    ]),
    ("2. Data yang kami kumpul", [
        "Maklumat akaun Google: nama dan alamat emel akaun Google anda. Log masuk hanya melalui "
        "Google – kami tidak menerima atau menyimpan kata laluan anda.",
        "Maklumat pelajar: nombor matrik, kursus, semester dan nombor telefon.",
        "Maklumat ibu bapa/penjaga: nama, alamat emel, nombor telefon dan hubungan.",
        "Aktiviti dalam aplikasi: program yang disertai, tarikh penyertaan, notifikasi dan "
        "status penghantaran emel kepada ibu bapa.",
        "Data teknikal: laporan ralat aplikasi (mesej ralat, jenis peranti/platform, versi "
        "aplikasi dan ID pengguna) untuk membaiki masalah. Kami tidak mengumpul lokasi, "
        "kenalan, gambar peribadi atau data pengiklanan.",
    ]),
    ("3. Tujuan penggunaan", [
        "Mendaftar dan mengurus akaun anda serta penyertaan program.",
        "Menghantar emel pengesahan, kemas kini dan pembatalan program kepada ibu bapa/penjaga "
        "yang anda namakan.",
        "Membolehkan pentadbir program menyediakan senarai peserta dan laporan.",
        "Keselamatan (mencegah penyalahgunaan) dan membaiki ralat aplikasi.",
        "Kami TIDAK menjual data anda, tidak menggunakan data untuk pengiklanan dan tidak "
        "berkongsi data dengan pihak ketiga untuk tujuan pemasaran.",
    ]),
    ("4. Persetujuan dan data ibu bapa", [
        "Dengan mendaftar, anda bersetuju dengan pemprosesan data seperti yang diterangkan di sini.",
        "Anda mengesahkan bahawa anda mendapat kebenaran ibu bapa/penjaga untuk memberikan "
        "maklumat hubungan mereka bagi tujuan notifikasi program.",
        "Pelajar di bawah 18 tahun hendaklah menggunakan aplikasi ini dengan pengetahuan dan "
        "kebenaran ibu bapa/penjaga.",
    ]),
    ("5. Siapa yang boleh melihat data anda", [
        "Anda: profil, penyertaan dan notifikasi anda sendiri sahaja. Pelajar lain tidak boleh "
        "melihat data anda.",
        "Pentadbir program (admin) yang dilantik: maklumat peserta program, log emel dan laporan. "
        "Setiap tindakan admin direkodkan dalam log audit.",
        "Pemproses data: Google Firebase (Authentication, Cloud Firestore, Realtime Database) "
        "untuk menyimpan data, dan EmailJS untuk menghantar emel kepada ibu bapa "
        "(menerima emel ibu bapa, nama pelajar dan butiran program).",
        "Pihak berkuasa jika dikehendaki oleh undang-undang.",
    ]),
    ("6. Lokasi penyimpanan", [
        "Data disimpan pada pelayan Google Cloud (Firebase), termasuk di Singapura dan Amerika "
        "Syarikat. Google melindungi data dengan penyulitan semasa penghantaran dan penyimpanan.",
    ]),
    ("7. Tempoh penyimpanan", [
        "Data akaun dan penyertaan disimpan selagi akaun anda aktif.",
        "Log penghantaran emel disimpan sehingga 12 bulan, kemudian dipadam oleh admin.",
        "Laporan ralat teknikal disimpan sehingga 90 hari.",
        "Salinan sandaran (backup) dibuat secara automatik setiap hari dan disimpan secara selamat "
        "dalam Google Drive akaun pasukan pembangun (akses terhad) untuk maksimum 90 hari.",
    ]),
    ("8. Padam akaun dan data", [
        "Dalam aplikasi: Profil → Padam akaun. Semua data anda (profil, maklumat ibu bapa, "
        "penyertaan, notifikasi dan log emel berkaitan) dipadam serta-merta dan akaun log masuk "
        "anda dipadam.",
        f"Tanpa aplikasi: layari {WEB}/delete-account atau emel {CONTACT} daripada alamat emel "
        "akaun anda. Permintaan diproses dalam masa 30 hari.",
        "Data dalam salinan sandaran akan hilang apabila sandaran tersebut tamat tempoh (maksimum "
        "90 hari). Rekod tanpa nama bahawa sebuah akaun telah dipadam disimpan untuk laporan.",
    ]),
    ("9. Hak anda", [
        "Mengakses dan membetulkan data anda pada bila-bila masa melalui skrin Profil.",
        "Menarik balik persetujuan dengan memadam akaun anda.",
        f"Membuat pertanyaan atau aduan kepada kami di {CONTACT}, atau kepada Jabatan "
        "Perlindungan Data Peribadi (JPDP) Malaysia.",
    ]),
    ("10. Keselamatan", [
        "Sambungan disulitkan (HTTPS/TLS). Akses data dikawal oleh peraturan keselamatan "
        "berasaskan peranan – setiap pelajar hanya boleh mengakses data sendiri, dan data admin "
        "disimpan dalam pangkalan data yang berasingan.",
        "Walaupun kami mengambil langkah munasabah, tiada sistem yang 100% selamat. Sila "
        "gunakan kata laluan yang kukuh dan jangan berkongsi akaun.",
    ]),
    ("11. Perubahan dasar", [
        "Jika dasar ini dikemas kini, tarikh berkuat kuasa akan ditukar dan aplikasi akan meminta "
        "persetujuan anda semula sebelum anda meneruskan.",
    ]),
]

ENGLISH_SUMMARY = [
    f"{APP} is a program registration app for {INSTITUTION} students. It collects your account "
    "details, student details and your parent/guardian's contact details to register you for "
    "programs and email your parent/guardian about them.",
    "Data is stored with Google Firebase and parent emails are sent through EmailJS. We do not "
    "sell data or use it for advertising.",
    "Only you and appointed program administrators can see your data; every admin action is "
    "audit-logged.",
    f"Delete your account any time in the app (Profile → Delete account), at "
    f"{WEB}/delete-account, or by emailing {CONTACT}.",
]

DELETE_TITLE = "Padam Akaun MyParentCare"
DELETE_STEPS = [
    "Buka aplikasi MyParentCare di telefon Android anda dan log masuk.",
    "Pergi ke tab Profil.",
    "Tekan “Padam akaun”, taip DELETE, kemudian log masuk semula dengan Google untuk mengesahkan.",
]
DELETE_DATA = [
    "Profil pelajar (nama, emel, nombor matrik, kursus, semester, telefon).",
    "Maklumat ibu bapa/penjaga (nama, emel, telefon, hubungan).",
    "Semua penyertaan program (tempat anda dilepaskan semula), notifikasi dan log emel ibu bapa berkaitan.",
    "Akaun log masuk Firebase Authentication anda.",
]
DELETE_KEPT = [
    "Rekod tanpa nama bahawa sebuah akaun telah dipadam (tarikh dan sebab pilihan) – tiada data peribadi.",
    "Salinan sandaran (backup) sedia ada akan tamat tempoh dalam masa maksimum 90 hari.",
]


# ----------------------------------------------------------------- Dart output

def dart_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("$", "\\$")


def write_dart() -> None:
    lines = [
        "// FAIL DIJANA oleh tool/generate_legal.py – jangan ubah secara manual.",
        "",
        "class LegalSection {",
        "  final String title;",
        "  final List<String> paragraphs;",
        "",
        "  const LegalSection(this.title, this.paragraphs);",
        "}",
        "",
        "class PrivacyContent {",
        "  PrivacyContent._();",
        "",
        f"  static const version = {dart_string(VERSION)};",
        f"  static const title = {dart_string(PRIVACY_TITLE)};",
        f"  static const intro = {dart_string(PRIVACY_INTRO)};",
        "",
        "  static const sections = <LegalSection>[",
    ]
    for title, paragraphs in PRIVACY_SECTIONS:
        lines.append(f"    LegalSection({dart_string(title)}, [")
        for p in paragraphs:
            lines.append(f"      {dart_string(p)},")
        lines.append("    ]),")
    lines += [
        "  ];",
        "",
        "  static const englishSummary = <String>[",
        *[f"    {dart_string(p)}," for p in ENGLISH_SUMMARY],
        "  ];",
        "",
        "  static const deletedData = <String>[",
        *[f"    {dart_string(p)}," for p in DELETE_DATA],
        "  ];",
        "",
        "  static const keptAfterDeletion = <String>[",
        *[f"    {dart_string(p)}," for p in DELETE_KEPT],
        "  ];",
        "}",
        "",
    ]
    out = ROOT / "lib/frontend/screens/legal/privacy_content.dart"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")


# ------------------------------------------------------------- Laman web muat turun
# Laman statik untuk Firebase project `website-81b96` (https://website-81b96.web.app).
# Aplikasi hanya untuk Android – laman ini TIDAK menjalankan aplikasi, ia hanya
# tempat memuat turun APK dan menempatkan Dasar Privasi / Padam Akaun (Play Store).

SITE = ROOT / "website" / "public"

# Kemas kini bahagian ini setiap kali APK baharu dimuat naik ke Google Drive.
APK_URL = "https://drive.google.com/file/d/1wwhw-m8AsSaP7CuI8OSvhRvMs9FUC_jY/view?usp=sharing"
APK_VERSION = "1.0.0"
APK_BUILD = "8"
APK_SIZE_MB = "24.6"
APK_SHA256 = "75427665e11b27f5f4931d77d80802fcc7b0bb66a53e562cfae544ea48eaf9c4"
MIN_ANDROID = "7.0"
PLAY_URL = ""  # Isi pautan Google Play apabila aplikasi diterbitkan.

NAV = [("/#ciri", "Ciri"), ("/#cara-pasang", "Cara pasang"), ("/#soalan", "Soalan lazim")]


def e(value: str) -> str:
    return html.escape(value, quote=True)


def layout(title: str, description: str, body: str, *, active: str = "") -> str:
    links = "".join(f'<a href="{href}">{e(label)}</a>' for href, label in NAV)
    return f"""<!DOCTYPE html>
<html lang="ms">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)}</title>
<meta name="description" content="{e(description)}">
<meta name="theme-color" content="#0969E8">
<meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(description)}">
<meta property="og:image" content="{WEB}/assets/logo-512.png">
<meta property="og:type" content="website">
<link rel="icon" type="image/png" href="/assets/favicon.png">
<link rel="apple-touch-icon" href="/assets/logo-192.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body class="{e(active)}">
<header class="nav">
  <div class="wrap nav-inner">
    <a class="brand" href="/"><img src="/assets/logo-192.png" alt="" width="36" height="36"><span>{APP}</span></a>
    <nav class="nav-links">{links}</nav>
    <a class="btn btn-sm" href="/#muat-turun">Muat turun</a>
  </div>
</header>
{body}
<footer class="footer">
  <div class="wrap footer-inner">
    <div>
      <a class="brand" href="/"><img src="/assets/logo-192.png" alt="" width="32" height="32"><span>{APP}</span></a>
      <p>Aplikasi pendaftaran program untuk pelajar {INSTITUTION}, dengan notifikasi automatik kepada ibu bapa.</p>
    </div>
    <div class="footer-links">
      <a href="/privacy">Dasar Privasi</a>
      <a href="/delete-account">Padam Akaun</a>
      <a href="mailto:{CONTACT}">{CONTACT}</a>
    </div>
  </div>
  <div class="wrap copyright">© 2026 {APP} · Untuk pelajar {INSTITUTION}</div>
</footer>
</body>
</html>
"""


def download_button(label: str = "Muat turun untuk Android", cls: str = "btn btn-lg") -> str:
    if not APK_URL:
        return '<span class="btn btn-lg btn-disabled">Pautan muat turun akan tersedia</span>'
    icon = ('<svg aria-hidden="true" viewBox="0 0 24 24" width="22" height="22"><path fill="currentColor" '
            'd="M12 3a1 1 0 0 1 1 1v9.59l3.3-3.3a1 1 0 1 1 1.4 1.42l-5 5a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 '
            '1.4-1.42l3.3 3.3V4a1 1 0 0 1 1-1Zm-7 14a1 1 0 0 1 1 1v1h12v-1a1 1 0 1 1 2 0v2a1 1 0 0 1-1 '
            '1H5a1 1 0 0 1-1-1v-2a1 1 0 0 1 1-1Z"/></svg>')
    return (f'<a class="{cls}" href="{e(APK_URL)}" target="_blank" rel="noopener">'
            f'{icon}<span>{e(label)}</span></a>')


def write_index() -> None:
    play = (f'<a class="btn btn-lg btn-ghost" href="{e(PLAY_URL)}" target="_blank" rel="noopener">Google Play</a>'
            if PLAY_URL else "")
    features = [
        ("student", "Untuk pelajar", "Cari program, sertai dengan satu tekanan, dan lihat semua program anda di satu tempat. Tempat anda dijamin serta-merta."),
        ("parent", "Untuk ibu bapa", "Ibu bapa atau penjaga menerima emel automatik setiap kali anak menyertai program, dan jika program dikemas kini atau dibatalkan."),
        ("admin", "Untuk penganjur", "Urus program, peserta, emel dan laporan. Setiap tindakan admin direkodkan dalam log audit."),
    ]
    icons = {
        "student": '<path d="M12 3 1 9l11 6 9-4.9V17h2V9L12 3Zm-7 9.2V16c0 1.7 3.1 4 7 4s7-2.3 7-4v-3.8l-7 3.8-7-3.8Z"/>',
        "parent": '<path d="M16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm-8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm0 2c-2.7 0-8 1.3-8 4v2h10v-2c0-1.1.4-2.1 1.2-3-1-.6-2.2-1-3.2-1Zm8 0c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4Z"/>',
        "admin": '<path d="M12 1 3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4Zm-1 15-4-4 1.4-1.4L11 13.2l5.6-5.6L18 9l-7 7Z"/>',
    }
    cards = "".join(
        f'<article class="card feature"><div class="icon icon-{k}"><svg viewBox="0 0 24 24" aria-hidden="true">{icons[k]}</svg></div>'
        f'<h3>{e(t)}</h3><p>{e(d)}</p></article>'
        for k, t, d in features
    )
    steps = [
        ("Log masuk dengan Google", "Tiada kata laluan baharu. Kali pertama, lengkapkan maklumat pelajar dan ibu bapa – ini wajib sebelum menyertai program."),
        ("Pilih program", "Lihat program yang dibuka, semak tarikh, lokasi, gambar dan tempat yang masih ada."),
        ("Ibu bapa dimaklumkan", "Tekan Join. Tempat anda disahkan dan ibu bapa menerima emel dengan butiran program."),
    ]
    step_html = "".join(
        f'<li class="step"><span class="step-no">{i}</span><div><h3>{e(t)}</h3><p>{e(d)}</p></div></li>'
        for i, (t, d) in enumerate(steps, 1)
    )
    install = [
        ("Muat turun APK", "Tekan butang Muat turun. Google Drive akan dibuka – tekan ikon muat turun (⤓) di atas."),
        ("Benarkan pemasangan", f"Buka fail <b>MyParentCare-v{APK_VERSION}-build{APK_BUILD}.apk</b>. Jika diminta, benarkan “Install unknown apps” untuk Chrome atau Files."),
        ("Pasang & log masuk", "Tekan Install, buka MyParentCare dan tekan “Log masuk dengan Google”. Selesai!"),
    ]
    install_html = "".join(
        f'<li class="step"><span class="step-no">{i}</span><div><h3>{e(t)}</h3><p>{d}</p></div></li>'
        for i, (t, d) in enumerate(install, 1)
    )
    faqs = [
        ("Adakah MyParentCare percuma?", "Ya. Aplikasi ini percuma untuk pelajar dan ibu bapa."),
        ("Perlukah saya cipta kata laluan?",
         "Tidak. Pelajar dan admin log masuk dengan akaun Google sahaja – lebih selamat dan tiada kata laluan untuk diingat."),
        ("Telefon saya kata aplikasi ini “tidak dikenali”. Selamat ke?",
         "Amaran ini biasa untuk aplikasi yang belum berada di Google Play. Muat turun hanya daripada butang di laman ini. "
         f"Anda boleh menyemak fail dengan cap jari SHA-256 di bawah."),
        ("Saya sudah pasang versi lama. Kenapa tidak boleh kemas kini?",
         "Versi lama ditandatangani dengan kunci berbeza. Nyahpasang (uninstall) MyParentCare lama dahulu, kemudian pasang versi baharu."),
        ("Adakah ada untuk iPhone?", "Belum. Buat masa ini MyParentCare hanya untuk telefon Android."),
        ("Siapa boleh melihat data saya?",
         "Hanya anda dan pentadbir program yang dilantik. Pelajar lain tidak boleh melihat maklumat anda atau ibu bapa anda. "
         'Baca <a href="/privacy">Dasar Privasi</a>.'),
        ("Bagaimana memadam akaun?", 'Dalam aplikasi: Profil → Padam akaun. Atau lihat <a href="/delete-account">halaman Padam Akaun</a>.'),
        ("Aplikasi ada masalah. Nak lapor di mana?", f'Emel kami di <a href="mailto:{CONTACT}">{CONTACT}</a> bersama tangkapan skrin.'),
    ]
    faq_html = "".join(f"<details><summary>{e(q)}</summary><p>{a}</p></details>" for q, a in faqs)

    body = f"""
<main>
<section class="hero">
  <div class="wrap hero-inner">
    <div class="hero-copy">
      <span class="pill"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 1 9l11 6 9-4.9V17h2V9L12 3Z"/></svg>Khas untuk pelajar {INSTITUTION}</span>
      <h1>Sertai program.<br><span class="grad">Ibu bapa sentiasa tahu.</span></h1>
      <p class="lead">{APP} memudahkan pelajar menyertai program kolej, dan menghantar butiran penyertaan kepada ibu bapa atau penjaga secara automatik melalui emel.</p>
      <div class="cta" id="muat-turun">
        {download_button()}
        {play}
      </div>
      <p class="meta">Android {MIN_ANDROID} ke atas · Versi {APK_VERSION} · {APK_SIZE_MB} MB · Percuma</p>
    </div>
    <div class="hero-art" aria-hidden="true">
      <div class="phone">
        <div class="screen">
          <div class="app-top"><img src="/assets/logo-192.png" alt=""><b>{APP}</b></div>
          <p class="hi">Hi, Aina 👋</p>
          <div class="app-card">
            <div class="app-banner"><span>CAREER</span></div>
            <div class="app-body">
              <div class="row"><b>Hari Kerjaya 2026</b><em>OPEN</em></div>
              <small>12 Dis 2026 · 9:00 pagi · Dewan Utama</small>
              <div class="bar"><i style="width:62%"></i></div>
              <small>23 tempat lagi</small>
              <span class="app-btn">JOIN PROGRAM</span>
            </div>
          </div>
          <div class="toast"><span>✓</span><div><b>Penyertaan disahkan</b><small>Emel dihantar kepada ibu bapa anda</small></div></div>
          <p class="mini-title">Program saya</p>
          <div class="mini"><i class="dot teal"></i><div><b>Futsal Antara Kelas</b><small>5 Dis · Gelanggang</small></div><em>SENT</em></div>
          <div class="mini"><i class="dot violet"></i><div><b>Bengkel Kepimpinan</b><small>18 Dis · Bilik Seminar</small></div><em>SENT</em></div>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="section" id="cara">
  <div class="wrap">
    <h2>Bagaimana ia berfungsi</h2>
    <ol class="steps">{step_html}</ol>
  </div>
</section>

<section class="section alt" id="ciri">
  <div class="wrap">
    <h2>Dibina untuk pelajar, ibu bapa dan penganjur</h2>
    <div class="grid">{cards}</div>
    <div class="trust">
      <div><b>Data dilindungi</b><span>Setiap pelajar hanya boleh melihat data sendiri.</span></div>
      <div><b>Tiada iklan</b><span>Data anda tidak dijual atau digunakan untuk iklan.</span></div>
      <div><b>Kawalan penuh</b><span>Padam akaun dan data anda pada bila-bila masa.</span></div>
    </div>
  </div>
</section>

<section class="section" id="cara-pasang">
  <div class="wrap narrow">
    <h2>Cara pasang di Android</h2>
    <ol class="steps">{install_html}</ol>
    <div class="cta center">{download_button("Muat turun APK")}</div>
    <p class="checksum"><span>SHA-256 build {APK_BUILD}</span><code>{APK_SHA256}</code></p>
  </div>
</section>

<section class="section alt" id="soalan">
  <div class="wrap narrow">
    <h2>Soalan lazim</h2>
    <div class="faq">{faq_html}</div>
  </div>
</section>
</main>
"""
    (SITE / "index.html").write_text(
        layout(f"{APP} – Program pelajar {INSTITUTION}",
               f"Muat turun {APP} untuk Android. Pelajar {INSTITUTION} menyertai program dan ibu bapa menerima emel automatik.",
               body, active="home"),
        encoding="utf-8",
    )


def write_legal_pages() -> None:
    parts = [f'<p class="meta">{e(PRIVACY_INTRO)}</p>']
    for title, paragraphs in PRIVACY_SECTIONS:
        items = "".join(f"<li>{e(p)}</li>" for p in paragraphs)
        parts.append(f'<section class="card legal"><h2>{e(title)}</h2><ul>{items}</ul></section>')
    summary = "".join(f"<li>{e(p)}</li>" for p in ENGLISH_SUMMARY)
    parts.append(f'<section class="card legal" lang="en"><h2>Summary in English</h2><ul>{summary}</ul></section>')
    body = f'<main class="page"><div class="wrap narrow"><h1>{e(PRIVACY_TITLE)}</h1>{"".join(parts)}</div></main>'
    (SITE / "privacy.html").write_text(
        layout(PRIVACY_TITLE, f"Dasar Privasi {APP} – bagaimana data pelajar dan ibu bapa dilindungi.", body),
        encoding="utf-8",
    )

    steps = "".join(f"<li>{e(s)}</li>" for s in DELETE_STEPS)
    deleted = "".join(f"<li>{e(s)}</li>" for s in DELETE_DATA)
    kept = "".join(f"<li>{e(s)}</li>" for s in DELETE_KEPT)
    mail = (f"mailto:{CONTACT}?subject=Permintaan%20padam%20akaun%20MyParentCare"
            "&body=Sila%20padam%20akaun%20MyParentCare%20saya.%0AEmel%20akaun%3A%20")
    body = f"""<main class="page"><div class="wrap narrow">
<h1>{e(DELETE_TITLE)}</h1>
<p class="meta">Anda boleh memadam akaun dan semua data peribadi anda pada bila-bila masa.</p>
<section class="card legal"><h2>Cara 1 – Dalam aplikasi (serta-merta)</h2><ol>{steps}</ol></section>
<section class="card legal"><h2>Cara 2 – Tanpa aplikasi</h2>
<p>Hantar emel daripada alamat emel akaun anda. Kami akan mengesahkan identiti anda dan memadam akaun dalam masa 30 hari.</p>
<a class="btn" href="{mail}">Emel {CONTACT}</a></section>
<section class="card legal"><h2>Data yang dipadam</h2><ul>{deleted}</ul></section>
<section class="card legal"><h2>Data yang disimpan selepas pemadaman</h2><ul>{kept}</ul></section>
</div></main>"""
    (SITE / "delete-account.html").write_text(
        layout(DELETE_TITLE, f"Cara memadam akaun dan data {APP}.", body), encoding="utf-8",
    )

    body = f"""<main class="page"><div class="wrap narrow center-text">
<h1>Halaman tidak dijumpai</h1>
<p class="lead">Pautan ini mungkin sudah lama atau salah taip.</p>
<p><a class="btn" href="/">Kembali ke laman utama</a></p>
</div></main>"""
    (SITE / "404.html").write_text(layout(f"Tidak dijumpai – {APP}", APP, body), encoding="utf-8")


if __name__ == "__main__":
    SITE.mkdir(parents=True, exist_ok=True)
    write_dart()
    write_index()
    write_legal_pages()
    print("Generated privacy_content.dart and website/public/{index,privacy,delete-account,404}.html")
