#!/usr/bin/env bash
# 用个人证书(.p12)和描述文件(.mobileprovision)重签未签名的 .app，输出可装到描述文件里登记的设备上的 IPA。
# 用法: resign-ipa.sh <未签名.app 路径> <输出.ipa 路径>
# 需要环境变量: IOS_P12_BASE64, IOS_P12_PASSWORD, IOS_PROFILE_BASE64
set -euo pipefail

APP_IN="$1"
IPA_OUT="$2"
WORK="$RUNNER_TEMP/resign"
rm -rf "$WORK" && mkdir -p "$WORK/Payload"

# 临时钥匙串，导入证书
KEYCHAIN="$WORK/signing.keychain-db"
KC_PASS="$(uuidgen)"
echo "$IOS_P12_BASE64" | base64 --decode > "$WORK/cert.p12"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$WORK/cert.p12" -P "$IOS_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$KC_PASS" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR==1{print $2}')"
[ -n "$IDENTITY" ] || { echo "::error::p12 里没有可用的签名身份（证书过期或密码错误？）"; exit 1; }
echo "签名身份: $(security find-identity -v -p codesigning "$KEYCHAIN" | head -1)"

# 解析描述文件
echo "$IOS_PROFILE_BASE64" | base64 --decode > "$WORK/profile.mobileprovision"
security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist"
PB=/usr/libexec/PlistBuddy
APP_ID="$($PB -c 'Print :Entitlements:application-identifier' "$WORK/profile.plist")"
TEAM_ID="${APP_ID%%.*}"
PROFILE_BUNDLE="${APP_ID#*.}"
EXPIRES="$($PB -c 'Print :ExpirationDate' "$WORK/profile.plist")"
echo "描述文件: App ID=$APP_ID, 过期时间=$EXPIRES"
$PB -x -c 'Print :Entitlements' "$WORK/profile.plist" > "$WORK/entitlements.plist"

cp -R "$APP_IN" "$WORK/Payload/"
APP="$WORK/Payload/$(basename "$APP_IN")"
BUNDLE_ID="$($PB -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

# 通配描述文件(TEAM.*)保留原 bundle id；精确描述文件则改成它要求的 bundle id
if [ "$PROFILE_BUNDLE" != "*" ]; then
  if [ "$PROFILE_BUNDLE" != "$BUNDLE_ID" ]; then
    echo "::warning::bundle id 改为描述文件要求的 $PROFILE_BUNDLE（原为 $BUNDLE_ID）"
    $PB -c "Set :CFBundleIdentifier $PROFILE_BUNDLE" "$APP/Info.plist"
  fi
  BUNDLE_ID="$PROFILE_BUNDLE"
fi
$PB -c "Set :application-identifier $TEAM_ID.$BUNDLE_ID" "$WORK/entitlements.plist"

cp "$WORK/profile.mobileprovision" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

# 先签内嵌的 framework / dylib / 扩展，最后签主 App
find "$APP" -depth \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' f; do
  codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" "$f"
done
codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --entitlements "$WORK/entitlements.plist" "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority" || true

(cd "$WORK" && zip -qry "$IPA_OUT" Payload)
security delete-keychain "$KEYCHAIN" || true
echo "已生成签名 IPA: $IPA_OUT"
