# Creates the upload keystore and android\key.properties. Run from C:\Development\research_app
# KEEP the .jks file and the passwords safe (password manager + a second backup).
# Never commit them. If you lose the upload key you must ask Google to reset it.
$ErrorActionPreference = 'Stop'
$ks = "$HOME\advantage-upload-key.jks"
if (Test-Path $ks) { throw "$ks already exists - not overwriting." }
$pw = Read-Host 'Choose a keystore password (min 6 chars)' -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
if ($plain.Length -lt 6) { throw 'Password too short' }
keytool -genkeypair -v -keystore $ks -alias upload -keyalg RSA -keysize 2048 -validity 10000 `
  -storepass $plain -keypass $plain -dname "CN=Advantage, OU=Wealthy, O=Wealthy, L=Mumbai, ST=Maharashtra, C=IN"
$path = $ks.Replace('\','/')
@"
storePassword=$plain
keyPassword=$plain
keyAlias=upload
storeFile=$path
"@ | Set-Content -Encoding ASCII android\key.properties
Write-Host "Created $ks and android\key.properties"
Write-Host "BACK UP the .jks file and password now."
