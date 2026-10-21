# Laman muat turun MyParentCare

Laman statik untuk https://website-81b96.web.app (Firebase project `website-81b96`).
Ia **bukan** versi web aplikasi – hanya tempat memuat turun APK Android, serta
Dasar Privasi dan Padam Akaun (URL untuk Google Play).

## Kemas kini pautan APK
1. Muat naik APK baharu ke Google Drive (kongsi: "Anyone with the link").
2. Ubah `APK_URL`, `APK_VERSION`, `APK_BUILD`, `APK_SIZE_MB`, `APK_SHA256` dalam
   `../tool/generate_legal.py` (checksum: `sha256sum fail.apk`).
3. Jana & deploy:
   ```bash
   python3 tool/generate_legal.py
   cd website && firebase deploy --only hosting
   ```
