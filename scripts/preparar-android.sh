#!/usr/bin/env bash
# Prepara el proyecto Android: permisos, ícono y firma fija (para poder actualizar sin desinstalar).
set -e
A=android
M=$A/app/src/main/AndroidManifest.xml
# Permiso de micrófono
if ! grep -q RECORD_AUDIO "$M"; then
  sed -i 's#</manifest>#    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <uses-permission android:name="android.permission.INTERNET" />\n    <queries><intent><action android:name="android.speech.RecognitionService" /></intent></queries>\n</manifest>#' "$M"
fi
# Orientación vertical
sed -i 's#android:name=".MainActivity"#android:name=".MainActivity"\n            android:screenOrientation="portrait"#' "$M"
# Ícono (colectivo) en todas las densidades
declare -A SZ=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
rm -rf $A/app/src/main/res/mipmap-anydpi-v26
for d in "${!SZ[@]}"; do
  D=$A/app/src/main/res/mipmap-$d
  mkdir -p $D
  rm -f $D/ic_launcher*.png $D/ic_launcher*.webp
  convert icon.png -resize ${SZ[$d]}x${SZ[$d]} $D/ic_launcher.png
  cp $D/ic_launcher.png $D/ic_launcher_round.png
  cp $D/ic_launcher.png $D/ic_launcher_foreground.png
done
# Firma fija: siempre la misma llave => los APK nuevos se instalan encima del anterior
G=$A/app/build.gradle
if ! grep -q "playaSigning" "$G"; then
  if [ -z "$PLAYA_KEYSTORE_B64" ] || [ -z "$PLAYA_KS_PASS" ]; then
    echo "ERROR: faltan los secretos PLAYA_KEYSTORE_B64 y PLAYA_KS_PASS (GitHub > Settings > Secrets and variables > Actions)."; exit 1
  fi
  echo "$PLAYA_KEYSTORE_B64" | base64 -d > $A/app/keystore.jks
  python3 - <<'PY'
g=open('android/app/build.gradle').read()
sign="""    signingConfigs {
        playaSigning {
            storeFile file('keystore.jks')
            storePassword System.getenv('PLAYA_KS_PASS')
            keyAlias 'playa'
            keyPassword System.getenv('PLAYA_KS_PASS')
        }
    }
"""
g=g.replace("    buildTypes {", sign+"    buildTypes {",1)
g=g.replace("    buildTypes {\n","    buildTypes {\n        debug {\n            signingConfig signingConfigs.playaSigning\n        }\n",1)
open('android/app/build.gradle','w').write(g)
PY
fi
echo "Android preparado."
