# renewHorizonCertViaAvi

## Important note

This script is not perfect and I'm sure there's much potential for improvement. For example it lacks several error handling scenarios for sure. But in any way, it does the job for my lab and it is sufficient for my own needs. Feel free to improve it.

I'm glad to help if needed - but I won't provide any support nor most likely not add any features.

## Description

The purpose of the script is to automatically update the certificate from Horizon Connection Server and from the Horizon Unified Access Gateway (UAG). On the Avi Controller the certificate will be renewed independently, e.g. by using the Let's Encrypt implementation.

This is useful when Avi is used as a load balancer in front of UAG or Horizon anyway, hence Avi always holds an up-to-date certificate for required domains.

This script is meant to be automatically run on the Horizon Connection Server Windows-host via Scheduled Tasks.

## Dependencies

I've tried to keep dependencies at a minimum, but there are still two dependencies:

1. The PowerShell Avi SDK to connect to Avi Controller
   - PowerShell modules available in the [Avi devops repository](https://github.com/avinetworks/devops/tree/master/powershell/AviSDK)

2. openssl for certificate conversion (PEM to PFX for Windows)
   - Windows binaries available at [wiki.openssl.org/index.php/Binaries](https://wiki.openssl.org/index.php/Binaries). I chose the [Win64 Light version here](https://slproweb.com/products/Win32OpenSSL.html).

The folder structure should look like:

```text
C:\data\certs\
                chain\
                        1_ISRG Root X1.crt
                        2_R3.crt
                script\
                        AviSDK\
                                AviSDK.psd1
                                AviSDK.psm1
                        openssl\ # containing openssl.exe directly
                        renewHorizonCertsViaAvi.ps1
```

Notes:

- All certificates in `C:\data\certs\chain\` are used to build a full-chain certificate. Certificates are used in alphabetic order in that folder.

## Configuration in PowerShell file

```text
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
```

### Example output

When certificate is already up-to-date from Avi:

```text
Runtime: 2023-04-14T20:00:01.9066051+02:00
Connecting to Avi...
Retrieving certificate...
Debug information:
  Certificate:
   - CN: vdi.domain.tld
   - Fingerprint: SHA1 Fingerprint=1F:B0:5E:83:CF:2A:A9:0A:CE:A5:65:C7:C9:99:7F:27:0F:2F:5A:62
   - Serial Number: 322974931524824104184204478434317415757667
Checking if certificate already active...
  Certificate active: 322974931524824104184204478434317415757667
Certificate already imported.
Exiting...
```

When update is needed:

```text
Runtime: 2023-03-25T21:17:10.2301793+01:00
Connecting to Avi...
Retrieving certificate...
Debug information:
  Certificate:
   - CN: vdi.domain.tld
   - Fingerprint: SHA1 Fingerprint=1F:B0:5E:83:CF:2A:A9:0A:CE:A5:65:C7:C9:99:7F:27:0F:2F:5A:62
   - Serial Number: 322974931524824104184204478434317415757667
Checking if certificate already active...
  Certificate active: 1FB05E83CF2EA90ACEA565C7C9997F070F2F5A62
Certificate already imported.
  Update needed...
Writing certificates to disk to C:\data\certs\...
Creating PEM file with full chain...
 Adding C:\data\certs\\chain\2_R3.crt to full chain...
 Adding C:\data\certs\\chain\1_ISRG Root X1.crt to full chain...
Updating UAG certificate...
Renaming old certificates...
 Renamed old certificate: 1FB05E83CF2EA90ACEA565C7C9997F070F2F5A62
Converting PEM to PFX via openssl...
Importing PFX certificate to local store...
Restarting wsbroker so new certificate takes effect...
Work done.
```
