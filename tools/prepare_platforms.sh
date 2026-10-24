#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case "${OSTYPE:-}" in
  msys*|cygwin*) exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/tools/prepare_platforms.ps1")" "$@" ;;
esac

force=0
case "${1:-}" in
  --force) force=1 ;;
  '') ;;
  *) echo 'Kullanım: bash tools/prepare_platforms.sh [--force]' >&2; exit 64 ;;
esac
command -v flutter >/dev/null 2>&1 || { echo 'HATA: Flutter SDK bulunamadı. Flutter 3.35+ kurup PATH’e ekleyin.' >&2; exit 127; }

android_complete=0
ios_complete=0
[[ -f android/gradlew ]] && android_complete=1
[[ -f ios/Runner.xcodeproj/project.pbxproj ]] && ios_complete=1
if [[ $force -eq 0 && $android_complete -eq 1 && $ios_complete -eq 1 ]]; then
  echo 'Android ve iOS iskeletleri zaten var. Yeniden üretmek için --force kullanın.'
  exit 0
fi
android_seed_only=1
if [[ -d android ]]; then
  while IFS= read -r f; do
    case "$f" in
      android/app/src/main/AndroidManifest.xml|android/key.properties|android/key.properties.example|android/*.jks|android/*.keystore) ;;
      *) android_seed_only=0 ;;
    esac
  done < <(find android -type f)
fi
if [[ $force -eq 0 && ( ( $android_complete -eq 0 && $android_seed_only -eq 0 ) || ( $ios_complete -eq 0 && -d ios && -n "$(find ios -type f -print -quit)" ) ) ]]; then
  echo 'UYARI: Kısmi platform iskeleti var. Var olanları korumak için otomatik üzerine yazılmadı.' >&2
  echo 'Eksik platformları üretmek ve var olanları yeniden oluşturmak için --force kullanın.' >&2
  exit 2
fi
replace_android=0
replace_ios=0
[[ $force -eq 1 || $android_complete -eq 0 ]] && replace_android=1
[[ $force -eq 1 || $ios_complete -eq 0 ]] && replace_ios=1

# Aynı dosya sisteminde staging: rename işlemleri güvenli olur ve TEMP farklı
# sürücüdeyse oluşabilecek taşıma hatası önlenir.
tmp="$(mktemp -d "$ROOT/.platform_staging.XXXXXX")"
committed=0
android_installed=0
ios_installed=0
cleanup() {
  local status=$?
  if [[ $committed -eq 0 ]]; then
    if [[ $android_installed -eq 1 ]]; then rm -rf android; fi
    if [[ $ios_installed -eq 1 ]]; then rm -rf ios; fi
    if [[ -d "$tmp/android.old" && ! -e android ]]; then mv "$tmp/android.old" android || true; fi
    if [[ -d "$tmp/ios.old" && ! -e ios ]]; then mv "$tmp/ios.old" ios || true; fi
  fi
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT
scaffold="$tmp/scaffold"
mkdir -p "$tmp/keep"

# Kullanıcının özel Android manifesti ve imza dosyalarını koru.
if [[ -f android/app/src/main/AndroidManifest.xml ]]; then
  mkdir -p "$tmp/keep/android/app/src/main"
  cp android/app/src/main/AndroidManifest.xml "$tmp/keep/android/app/src/main/AndroidManifest.xml"
fi
preserve_files=()
shopt -s nullglob
for f in android/key.properties android/*.jks android/*.keystore android/app/*.jks android/app/*.keystore; do
  [[ -f "$f" ]] && preserve_files+=("$f")
done
shopt -u nullglob
for f in ${preserve_files[@]+"${preserve_files[@]}"}; do
  mkdir -p "$tmp/keep/$(dirname "$f")"
  cp "$f" "$tmp/keep/$f"
done

flutter create --org com.santiyeagi --project-name santiye_agi --platforms android,ios "$scaffold"
test -f "$scaffold/android/gradlew" || { echo 'HATA: Android Gradle iskeleti eksik.' >&2; exit 1; }
test -f "$scaffold/ios/Runner.xcodeproj/project.pbxproj" || { echo 'HATA: iOS Xcode iskeleti eksik.' >&2; exit 1; }
if [[ -f "$tmp/keep/android/app/src/main/AndroidManifest.xml" ]]; then
  cp "$tmp/keep/android/app/src/main/AndroidManifest.xml" "$scaffold/android/app/src/main/AndroidManifest.xml"
fi
for f in ${preserve_files[@]+"${preserve_files[@]}"}; do
  rel="${f#android/}"
  mkdir -p "$scaffold/android/$(dirname "$rel")"
  cp "$tmp/keep/$f" "$scaffold/android/$rel"
done

# Önce eski klasörleri staging içine taşı, ardından yeni iskeleti yerleştir.
# Herhangi bir adım başarısız olursa EXIT trap eski klasörleri geri koyar.
if [[ $replace_android -eq 1 ]]; then
  if [[ -e android ]]; then mv android "$tmp/android.old"; fi
  mv "$scaffold/android" android
  android_installed=1
fi
if [[ $replace_ios -eq 1 ]]; then
  if [[ -e ios ]]; then mv ios "$tmp/ios.old"; fi
  mv "$scaffold/ios" ios
  ios_installed=1
fi

if command -v dart >/dev/null 2>&1; then
  dart tools/patch_platforms.dart
else
  "$(dirname "$(command -v flutter)")/dart" tools/patch_platforms.dart
fi

if command -v dart >/dev/null 2>&1; then
  dart tools/apply_app_icons.dart
else
  "$(dirname "$(command -v flutter)")/dart" tools/apply_app_icons.dart
fi
committed=1
echo 'Platform iskeletleri oluşturuldu ve özel dosyalar korundu.'
echo 'Sonraki adım: bash tools/verify_project.sh'
