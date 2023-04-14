param(
    [switch] $Force
)

Set-Location $PSScriptRoot
Import-Module -Name .\AviSDK\AviSDK.psd1
Disable-AviCertificateWarnings

### Credentials
$avi_host      = "<AVI_CONTROLLER_HOSTNAME>"
$avi_user      = "<USERNAME>" # e.g. admin
$avi_pass      = "<PASSWORD>"
$avi_tenant    = "<TENANT_NAME>" # usually admin
$avi_cert_name = "<NAME OF CERTIFICATE>" # e.g. VDI RSA

$uag_host      = "<HOST OF UAG>"
$uag_user      = "<USER OF UAG>" # usually admin
$uag_pass      = "<PASS OF UAG>"

$cert_password = "Password123%" # any random password used to temporary encrypt/decrypt certificate
$path          = "C:\data\certs\" # temporary folder where to store certificates

### Code
Write-Host "Runtime: $(Get-Date -format 'o')"

# Get certificate from Avi
Write-Host "Connecting to Avi..."
$AviSession = New-AviSession -Controller $avi_host -Username $avi_user -Password $avi_pass -Tenant $avi_tenant -ApiVersion "22.1.3"
Write-Host "Retrieving certificate..."
$cert_object = Get-AviObjectByName -AviSession $AviSession -ObjectType sslkeyandcertificate -Name $avi_cert_name -QueryParams @{export_key="True"}

if (!$cert_object) {
    throw "Certificate object is null. Error. Exiting."
    exit 1
}

# Save a few bits
$cert = $cert_object.certificate.certificate
$key = $cert_object.key

$cn = $cert_object.certificate.subject.common_name
$fingerprint = $cert_object.certificate.fingerprint.Replace("`n", "")
$serialnumber = $cert_object.certificate.serial_number

# Some debug output
Write-Host "Debug information:"
Write-Host "  Certificate:"
Write-Host "   - CN: $cn"
Write-Host "   - Fingerprint: $fingerprint"
Write-Host "   - Serial Number: $serialnumber"

# Get current active VDM cert
Write-Host "Checking if certificate already active..."
$cert_active = Get-Childitem -Path cert:\LocalMachine\My | Where-Object {$_.FriendlyName -eq 'vdm'}
if ($cert_active) {
    $cert_object_tp = $fingerprint.Replace("SHA1 Fingerprint=", "").Replace(":", "").Trim()
    $cert_active_tp = $cert_active.Thumbprint.Trim()
    Write-Host "  Certificate active: $cert_active_tp"
    if ($cert_object_tp -eq $cert_active_tp) {
        Write-Host "Certificate already imported."
        if (!$Force.IsPresent) {
            Write-Host "Exiting..."
            exit 0
        }
    }
    Write-Host "  Update needed..."
}

# Export current certificate
Write-Host "Writing certificates to disk to $path..."
New-Item -Path $path -ItemType Directory -Force | Out-Null
$cert | Out-File -FilePath "$path\vdi.crt" -NoNewline -Encoding utf8
$key  | Out-File -FilePath "$path\vdi.key" -NoNewline -Encoding utf8

$cert_password_secure = ConvertTo-SecureString $cert_password -AsPlainText -Force

# Make PEM file with full chain of LetsEncrypt
# Order: domain - intermed - root
Write-Host "Creating PEM file with full chain..."

$certs_chain = Get-ChildItem -Path "$path\chain\" | Sort-Object Name -Descending
$cert_chain = ""
ForEach ($certs_chain_file in $certs_chain) {
    Write-Host " Adding $path\chain\$certs_chain_file to full chain..."
    $cert_chain += (Get-Content -Path "$path\chain\$certs_chain_file" -Raw).Trim() + "`n"
}
$cert_chain | Out-File -FilePath "$path\vdi_chain.crt" -NoNewline -Encoding utf8

$cert_full = $cert + "`n" + $cert_chain
$cert_full | Out-File -FilePath "$path\vdi.pem" -NoNewline -Encoding utf8

#$cert_line_cert = $cert_object.certificate.certificate.Replace("`n",'\n').Trim()
$cert_line_key = $key.Replace("`n",'\n').Replace("`r", "").Trim()
$cert_line_full = $cert_full.Replace("`n",'\n').Replace("`r", "").Trim()

# Update UAG certificate
Write-Host "Updating UAG certificate..."
# Replace cert on UAG with REST API call
$uag_creds = [System.Text.Encoding]::UTF8.GetBytes("${uag_user}:${uag_pass}")
$uag_creds_base64 = [System.Convert]::ToBase64String($uag_creds)
$uag_api_default = @{
    ContentType = "application/json"
    Headers     = @{"Authorization" = "Basic $uag_creds_base64"}
    Method      = "PUT"
}

$uag_api_payload = '{"privateKeyPem":"' + $cert_line_key + '","certChainPem":"' + $cert_line_full + '"}'
$uag_api_url = "https://" + $uag_host + ":9443/rest/v1/config/certs/ssl/end_user"

$uag_api_payload = $uag_api_default + @{Body = $uag_api_payload}
Invoke-RestMethod $uag_api_url @uag_api_payload | Out-Null

# Update Horizon thumbprint
## THIS OVERWRITES ALL SETTINGS! WON'T BE MERGED WITH EXISTING UAG SETTINGS!
#Write-Host "Updating Horizon thumbprint..."
#$uag_api_payload = '{"identifier":"VIEW","proxyDestinationUrlThumbprints":"' + $sha1Fingerprint + '"}'
#$uag_api_url = "https://" + $uag_host + ":9443/rest/v1/config/edgeservice/view"
#$uag_api_payload = $uag_api_default + @{Body = $uag_api_payload}
#Invoke-RestMethod $uag_api_url @uag_api_payload | Out-Null

# Rename current certificates
Write-Host "Renaming old certificates..."
$old_certs = Get-Childitem -Path cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq 'vdm' }
ForEach ($old_cert in $old_certs) {
    $old_cert.FriendlyName = "vdm (Replaced $(Get-Date -format 'o'))"
    $old_tp = $old_cert.Thumbprint
    Write-Host " Renamed old certificate: $old_tp"
}

# Convert PEM to PFX
Write-Host "Converting PEM to PFX via openssl..."
Start-Process -Wait -NoNewWindow -FilePath ".\openssl\openssl.exe" -ArgumentList "pkcs12 -export -in `"$path\vdi.crt`" -CAfile `"$path\vdi_chain.crt`" -inkey `"$path\vdi.key`" -out `"$path\vdi.pfx`" -name `"vdm`" -passout `"pass:$cert_password`""

# Import PFX certificate into certificate store
Write-Host "Importing PFX certificate to local store..."
$cert_import_obj = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2("$path\vdi.pfx", $cert_password_secure, "Exportable,MachineKeySet,PersistKeySet")
$cert_store = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
$cert_store.Open('MaxAllowed')
$cert_store.Add($cert_import_obj)
$cert_store.Close()

# Change friendlyName of new certificate
if ($cert_new) {
    if ($cert_new.FriendlyName -ne "vdm") {
        Write-Host "  Renaming new certificate with FriendlyName=vdm..."
        $cert_new.FriendlyName = "vdm"
    }
}

# Restart Horizon Connection Server service
Write-Host "Restarting wsbroker so new certificate takes effect..."
Restart-Service -Name wsbroker

Write-Host "Work done."
exit 0
