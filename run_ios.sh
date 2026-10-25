#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$ROOT_DIR/flutter"
IOS_LIB_DIR="$ROOT_DIR/target/aarch64-apple-ios/release"
IOS_LIB_FILE="$IOS_LIB_DIR/liblibrustdesk.a"
PREBUILT_GZ="$ROOT_DIR/prebuilt/ios/liblibrustdesk.a.gz"
PBXPROJ="$FLUTTER_DIR/ios/Runner.xcodeproj/project.pbxproj"

echo "===================================================="
echo "🚀 RustDesk iOS (DeskIn UI) - One-Command Builder"
echo "===================================================="

# 1. Tìm Flutter SDK (ưu tiên FVM 3.35.5 hoặc flutter trong PATH)
if [ -x "$HOME/fvm/versions/3.35.5/bin/flutter" ]; then
  export PATH="$HOME/fvm/versions/3.35.5/bin:$PATH"
elif [ -x "$HOME/fvm/default/bin/flutter" ]; then
  export PATH="$HOME/fvm/default/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Không tìm thấy lệnh 'flutter'. Vui lòng cài đặt Flutter (khuyến nghị 3.35.5 qua FVM)."
  exit 1
fi
echo "✅ Flutter: $(which flutter)"

# 2. Giải nén sẵn thư viện lõi Rust (liblibrustdesk.a) nếu chưa có
if [ ! -f "$IOS_LIB_FILE" ]; then
  if [ -f "$PREBUILT_GZ" ]; then
    echo "📦 Đang giải nén thư viện lõi Rust (prebuilt/ios/liblibrustdesk.a.gz)..."
    mkdir -p "$IOS_LIB_DIR"
    gunzip -c "$PREBUILT_GZ" > "$IOS_LIB_FILE"
    echo "✅ Đã giải nén xong: $IOS_LIB_FILE"
  else
    echo "❌ Thiếu file $IOS_LIB_FILE và không tìm thấy gói $PREBUILT_GZ"
    exit 1
  fi
else
  echo "✅ Đã có sẵn thư viện lõi Rust: $IOS_LIB_FILE"
fi

# 3. Tự động phát hiện Apple Development Team ID trên máy Mac hiện tại
DETECTED_TEAM_ID="${TEAM_ID:-}"
if [ -z "$DETECTED_TEAM_ID" ]; then
  DETECTED_TEAM_ID="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' \
    | head -n 1 || true)"
fi

if [ -z "$DETECTED_TEAM_ID" ]; then
  echo "⚠️ Chưa tìm thấy chứng chỉ Apple Development trong Keychain."
  echo "👉 Hãy mở Xcode -> Settings (⌘,) -> Accounts -> đăng nhập Apple ID cá nhân."
  open -a Xcode "$FLUTTER_DIR/ios/Runner.xcworkspace" || true
  read -r -p "Nhập DEVELOPMENT_TEAM (10 ký tự) hoặc nhấn Enter sau khi đã chọn Team trong Xcode: " INPUT_TEAM
  if [ -n "$INPUT_TEAM" ]; then
    DETECTED_TEAM_ID="$INPUT_TEAM"
  else
    DETECTED_TEAM_ID="$(grep -m1 "DEVELOPMENT_TEAM = " "$PBXPROJ" | sed -E 's/.*DEVELOPMENT_TEAM = ([A-Z0-9]+);.*/\1/' || true)"
  fi
fi

if [ -z "$DETECTED_TEAM_ID" ]; then
  echo "❌ Không xác định được DEVELOPMENT_TEAM."
  exit 1
fi

# Tự động chọn Bundle ID theo Team ID để không bị trùng giữa các tài khoản Apple Free khác nhau
if [ -n "${BUNDLE_ID:-}" ]; then
  TARGET_BUNDLE_ID="$BUNDLE_ID"
elif [ "$DETECTED_TEAM_ID" = "4NHCV2V5U5" ]; then
  TARGET_BUNDLE_ID="com.thinhnnd.rustdesk"
else
  LOWER_TEAM="$(echo "$DETECTED_TEAM_ID" | tr '[:upper:]' '[:lower:]')"
  TARGET_BUNDLE_ID="com.rustdesk.ios.${LOWER_TEAM}"
fi

echo "✅ Apple Team ID : $DETECTED_TEAM_ID"
echo "✅ Bundle ID     : $TARGET_BUNDLE_ID"

# Cập nhật DEVELOPMENT_TEAM và PRODUCT_BUNDLE_IDENTIFIER trong project.pbxproj
sed -i '' -E "s/DEVELOPMENT_TEAM = [A-Za-z0-9_]+;/DEVELOPMENT_TEAM = ${DETECTED_TEAM_ID};/g" "$PBXPROJ"
sed -i '' -E "s/PRODUCT_BUNDLE_IDENTIFIER = [A-Za-z0-9._-]+;/PRODUCT_BUNDLE_IDENTIFIER = ${TARGET_BUNDLE_ID};/g" "$PBXPROJ"

# 4. Tìm danh sách iPhone / iPad thật đang kết nối
DEVICES_RAW="$(xcrun devicectl list devices 2>/dev/null | grep "physical" | grep -E "connected|available" || true)"
DEVICE_UDIDS=()
while IFS= read -r line; do
  udid="$(echo "$line" | sed -n 's/.* \([0-9A-Fa-f-]\{24,\}\) (UDID).*/\1/p')"
  if [ -n "$udid" ]; then
    DEVICE_UDIDS+=("$udid")
  fi
done <<< "$DEVICES_RAW"

if [ "${#DEVICE_UDIDS[@]}" -eq 0 ]; then
  echo "⚠️ Không tìm thấy iPhone/iPad nào đang cắm cáp (hoặc chưa mở khóa/Trust máy tính)."
  echo "   Vẫn tiếp tục build file Runner.app..."
else
  echo "📱 Thiết bị phát hiện: ${DEVICE_UDIDS[*]}"
fi

# 5. Build Flutter iOS Release (tự động đăng ký UDID thiết bị mới nếu cần)
cd "$FLUTTER_DIR"
flutter pub get

if ! flutter build ios --release; then
  if [ "${#DEVICE_UDIDS[@]}" -gt 0 ]; then
    FIRST_UDID="${DEVICE_UDIDS[0]}"
    echo "🔄 Đang tự động đăng ký thiết bị ($FIRST_UDID) vào Provisioning Profile của Apple ID..."
    xcodebuild -workspace ios/Runner.xcworkspace \
      -scheme Runner \
      -configuration Release \
      -destination "id=$FIRST_UDID" \
      -allowProvisioningUpdates \
      -allowProvisioningDeviceRegistration \
      build
    flutter build ios --release
  else
    exit 1
  fi
fi

# 6. Cài đặt và khởi chạy trên toàn bộ iPhone / iPad đang kết nối
APP_PATH="$FLUTTER_DIR/build/ios/iphoneos/Runner.app"
for udid in "${DEVICE_UDIDS[@]}"; do
  echo "📲 Đang cài đặt lên thiết bị $udid..."
  if xcrun devicectl device install app --device "$udid" "$APP_PATH"; then
    echo "🚀 Đang mở app ($TARGET_BUNDLE_ID) trên $udid..."
    xcrun devicectl device process launch --device "$udid" "$TARGET_BUNDLE_ID" || true
  fi
done

# Khôi phục project.pbxproj về mặc định nếu đã đổi sang Team khác để không làm bẩn git status
if [ "$DETECTED_TEAM_ID" != "4NHCV2V5U5" ]; then
  git checkout -- "$PBXPROJ" 2>/dev/null || true
fi

echo "===================================================="
echo "🎉 Hoàn tất! Nếu đây là lần đầu cài trên iPhone mới:"
echo "   Vào Cài đặt -> Cài đặt chung -> Quản lý VPN & Thiết bị -> Tin cậy (Trust) Apple ID."
echo "===================================================="
