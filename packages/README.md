# EasyServ-Pakete

Die Pakete werden aus den Upstream-Quellen gebaut, für den festen Installationsort
`/Applications/EasyServ/package/<name>/<major>/<version>`.

## Bauen
```sh
brew install pkgconf cmake          # nur Build-Werkzeuge, werden nicht gelinkt
make packages PACKAGES="nginx php-8.5 php-8.4"
ARCH=x86_64 make packages PACKAGES=nginx   # Intel (über Rosetta / auf Intel-Runnern)
```
- Quellen, Versionen und SHA-256 stehen in `sources.lock`. Downloads werden vor dem Entpacken geprüft.
- Fremdbibliotheken (OpenSSL, PCRE2, ICU, libzip, Oniguruma, libsodium, libpng, libjpeg-turbo, FreeType, libwebp) werden statisch gebaut (`recipes/deps.sh`) und fest eingelinkt. Die Pakete hängen deshalb nur von macOS-Systembibliotheken ab; `check_linkage` erzwingt das.
- Gebaut wird mit `DESTDIR`-Staging, also ohne Root. Ausgabe: `build/packages/dist/<name>-<version>-<arch>.tar.gz` plus Manifest (`.json`).

## Paketformat
Das Archiv enthält genau ein Verzeichnis `<version>/` und darin `easyserv-package.json`:
```json
{ "schema": 1, "name": "php", "major": "8.5", "version": "8.5.12", "arch": "arm64", "minMacOS": "13.0",
  "category": "language", "service": "php",
  "links": { "bin": ["bin/php", "bin/phpize"] }, "shims": ["php", "phpize"] }
```

## Katalog
```sh
make catalog                              # dist/catalog.json + catalog.json.sig (Dev-Schlüssel)
make catalog BASE_URL=https://…/packages  # absolute Download-URLs
make dev-catalog                          # installierte App auf den lokalen Katalog umstellen
```
- Signatur: Ed25519 über die exakten Bytes von `catalog.json`. Der private Schlüssel liegt außerhalb des Repos (`~/.easyserv/catalog-signing-dev.key`), die vertrauenswürdigen öffentlichen Schlüssel stehen in `Shared/CatalogTrust.swift`.
- Der Helper prüft Signatur, Prüfsumme, Archivpfade, Symlinks und Manifest selbst, bevor er ein Paket root-eigen nach `package/` verschiebt (`Helper/PackageInstaller.swift`).
