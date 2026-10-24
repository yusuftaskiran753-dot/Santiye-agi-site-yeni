#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v flutter >/dev/null 2>&1 || { echo 'HATA: Flutter SDK bulunamadı. Flutter 3.35+ kurup PATH’e ekleyin.' >&2; exit 127; }
flutter --version
if [[ ! -f android/gradlew || ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo 'Platform dosyaları eksik; önce bash tools/prepare_platforms.sh çalıştırın.' >&2
  exit 2
fi
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test

# Yayın paketleri demo ayarlarıyla sessizce derlenmesin. Değerler CI secret'ları
# veya yerel shell değişkenleri olarak verilebilir; sırlar repoya yazılmamalıdır.
require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "HATA: Yayın derlemesi için $name ortam değişkeni zorunludur." >&2
    exit 3
  fi
}
release_defines() {
  local name
  for name in OPERATOR_NAME SUPPORT_EMAIL TERMS_URL PRIVACY_URL KVKK_URL ACCOUNT_DELETION_URL MAP_TILE_URL MAP_ATTRIBUTION; do
    require_env "$name"
  done
  if [[ -n "${API_BASE_URL:-}" ]]; then
    [[ "$API_BASE_URL" == https://* ]] || { echo 'HATA: Canlı API_BASE_URL HTTPS olmalı.' >&2; exit 3; }
    BACKEND_DEFINES=("--dart-define=API_BASE_URL=$API_BASE_URL")
  else
    require_env SUPABASE_URL
    require_env SUPABASE_KEY
    [[ "$SUPABASE_URL" == https://*.supabase.co ]] || { echo 'HATA: SUPABASE_URL https://...supabase.co biçiminde olmalı.' >&2; exit 3; }
    [[ "$SUPABASE_KEY" != *service_role* && "$SUPABASE_KEY" != sb_secret_* ]] || { echo 'HATA: İstemciye service_role/secret anahtarı verilemez; publishable/anon anahtarı kullanın.' >&2; exit 3; }
    BACKEND_DEFINES=("--dart-define=SUPABASE_URL=$SUPABASE_URL" "--dart-define=SUPABASE_KEY=$SUPABASE_KEY")
  fi
  [[ "$MAP_TILE_URL" == https://* ]] || { echo 'HATA: MAP_TILE_URL HTTPS adresi olmalı.' >&2; exit 3; }
  [[ "$TERMS_URL" == https://* && "$PRIVACY_URL" == https://* && "$KVKK_URL" == https://* && "$ACCOUNT_DELETION_URL" == https://* ]] || { echo 'HATA: Kullanım koşulları, gizlilik, KVKK ve hesap silme adresleri HTTPS olmalı.' >&2; exit 3; }
  [[ "$SUPPORT_EMAIL" == *@*.* ]] || { echo 'HATA: SUPPORT_EMAIL geçerli bir destek e-posta adresi olmalı.' >&2; exit 3; }
  [[ "$MAP_TILE_URL" != 'https://tile.openstreetmap.org/{z}/{x}/{y}.png' ]] || { echo 'HATA: Üretim derlemesi için ticari kullanım koşullarına uygun bir harita sağlayıcısı seçin; standart OSM karo sunucusu yayın kapısı olarak kabul edilmez.' >&2; exit 3; }
  [[ "$MAP_ATTRIBUTION" != '© OpenStreetMap katkıda bulunanlar' ]] || { echo 'HATA: Seçilen harita sağlayıcısının doğru atıf metnini MAP_ATTRIBUTION ile verin.' >&2; exit 3; }
  RELEASE_DEFINES=(
    "${BACKEND_DEFINES[@]}"
    "--dart-define=OPERATOR_NAME=$OPERATOR_NAME"
    "--dart-define=SUPPORT_EMAIL=$SUPPORT_EMAIL"
    "--dart-define=TERMS_URL=$TERMS_URL"
    "--dart-define=PRIVACY_URL=$PRIVACY_URL"
    "--dart-define=KVKK_URL=$KVKK_URL"
    "--dart-define=ACCOUNT_DELETION_URL=$ACCOUNT_DELETION_URL"
    "--dart-define=MAP_TILE_URL=$MAP_TILE_URL"
    "--dart-define=MAP_ATTRIBUTION=$MAP_ATTRIBUTION"
    "--dart-define=SHOW_SAMPLE_LISTINGS=false"
  )
}
check_android_signing() {
  [[ -f android/key.properties ]] || { echo 'HATA: android/key.properties yok. android/key.properties.example dosyasını kopyalayıp gerçek değerleri girin.' >&2; exit 3; }
  grep -q '^storePassword=.' android/key.properties || { echo 'HATA: storePassword eksik.' >&2; exit 3; }
  grep -q '^keyPassword=.' android/key.properties || { echo 'HATA: keyPassword eksik.' >&2; exit 3; }
  grep -q '^keyAlias=.' android/key.properties || { echo 'HATA: keyAlias eksik.' >&2; exit 3; }
  local store_file
  store_file="$(sed -n 's/^storeFile=//p' android/key.properties | tail -n 1)"
  [[ -n "$store_file" && -f "$store_file" ]] || { echo 'HATA: key.properties içindeki storeFile bulunamadı.' >&2; exit 3; }
  if grep -Eqi 'ANAHTAR|kullanici|CHANGEME|TODO' android/key.properties; then
    echo 'HATA: android/key.properties hâlâ örnek/yer tutucu değer içeriyor.' >&2; exit 3
  fi
}

case "${1:-}" in
  android)
    release_defines
    check_android_signing
    flutter build appbundle --release "${RELEASE_DEFINES[@]}"
    ;;
  apk)
    release_defines
    check_android_signing
    flutter build apk --release "${RELEASE_DEFINES[@]}"
    ;;
  ios)
    if [[ "$(uname -s)" != "Darwin" ]]; then
      echo 'iOS derlemesi için macOS ve Xcode gerekir.' >&2; exit 2
    fi
    release_defines
    flutter build ipa --release "${RELEASE_DEFINES[@]}"
    ;;
  '')
    echo 'Kod analizi ve testler tamamlandı. Yayın paketi için argüman: android | apk | ios'
    ;;
  *) echo 'Kullanım: bash tools/verify_project.sh [android|apk|ios]' >&2; exit 64 ;;
esac
