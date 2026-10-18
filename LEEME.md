# Playa y Combustible — APK

## Cómo obtener el APK (desde la PC, ~10 minutos, gratis)
1. Entrá a github.com → creá una cuenta (si no tenés) → botón **New repository** → nombre `playa-apk` → **Create**.
2. En el repositorio nuevo: **uploading an existing file**. Descomprimí este zip y arrastrá TODO el contenido
   (incluida la carpeta `.github`) a la página. Abajo: **Commit changes**.
3. Pestaña **Actions** → "Compilar APK" (arranca solo; si no, **Run workflow**). Tarda 5-8 min.
4. Cuando termine con ✔ verde, entrá a esa corrida → abajo en **Artifacts** → descargá `Playa-y-Combustible-APK` (zip con `app-debug.apk`).
5. Pasá el APK al celular (WhatsApp, cable o Drive) y abrilo. Android pide permitir "instalar apps desconocidas": aceptar una vez.

## Para actualizar
Cambiás los archivos de la carpeta `www` en GitHub y se compila un APK nuevo. Se instala encima del anterior sin perder datos (la firma es fija).

## Micrófono
Usa el reconocimiento de voz nativo de Android (servicio de Google), en español de Argentina. Funciona igual en cualquier celular que tenga la app "Google" instalada.
En el primer uso pide permiso de micrófono: aceptar.
