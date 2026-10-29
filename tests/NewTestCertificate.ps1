# Test-only in-memory key and certificate. Never installs a trust certificate in Windows.
param([Parameter(Mandatory=$true)][string]$OutputDir)
$ErrorActionPreference='Stop'
[void][IO.Directory]::CreateDirectory($OutputDir)
$rsa=[Security.Cryptography.RSA]::Create(2048)
try {
    $request=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=127.0.0.1',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $san=[Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $san.AddIpAddress([Net.IPAddress]::Parse('127.0.0.1'))
    $san.AddDnsName('localhost')
    $request.CertificateExtensions.Add($san.Build())
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))
    $certificate=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5),[DateTimeOffset]::UtcNow.AddDays(1))
    try {
        [IO.File]::WriteAllText((Join-Path $OutputDir 'certificate.pem'),$certificate.ExportCertificatePem())
        [IO.File]::WriteAllText((Join-Path $OutputDir 'key.pem'),$rsa.ExportPkcs8PrivateKeyPem())
    } finally { $certificate.Dispose() }
} finally { $rsa.Dispose() }
