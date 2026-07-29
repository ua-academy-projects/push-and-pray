[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$secretDirectory = Join-Path $HOME ".config\aegis"

function Write-SecretFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $path = Join-Path $secretDirectory $Name
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        Write-Host "Keeping existing secret: $path"
        return
    }
    [System.IO.File]::WriteAllText($path, $Value)
    Write-Host "Created secret: $path"
}

function New-RandomPassword {
    $bytes = New-Object byte[] 24
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }
    return ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
}

function ConvertFrom-SecureValue {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$Value
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null

$apiKeyPath = Join-Path $secretDirectory "abuseipdb-api-key"
if ($Force -or -not (Test-Path -LiteralPath $apiKeyPath)) {
    $secureApiKey = Read-Host "Enter the AbuseIPDB API key" -AsSecureString
    $apiKey = ConvertFrom-SecureValue -Value $secureApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "The AbuseIPDB API key cannot be empty."
    }
    Write-SecretFile -Name "abuseipdb-api-key" -Value $apiKey
}
else {
    Write-Host "Keeping existing secret: $apiKeyPath"
}

@(
    "mariadb-password",
    "mariadb-root-password",
    "rabbitmq-provider-password",
    "rabbitmq-history-password",
    "rabbitmq-admin-password",
    "redis-ui-password"
) | ForEach-Object {
    Write-SecretFile -Name $_ -Value (New-RandomPassword)
}

Write-Host ""
Write-Host "AEGIS Vagrant secrets are ready."
Write-Host "Run: vagrant validate"
Write-Host "Run: vagrant up"
