param(
    [Parameter(Mandatory = $true)]
    [string]$StartScript,
    [Parameter(Mandatory = $true)]
    [string]$LogFile,
    [Parameter(Mandatory = $true)]
    [string]$LatestLog,
    [Parameter(Mandatory = $true)]
    [string]$StateFile,
    [Parameter(Mandatory = $true)]
    [string]$PidFile,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThroughArgs
)

$ErrorActionPreference = "Continue"

function Append-LogText {
    param([string]$Text)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($LatestLog, $Text, $utf8NoBom)
    [System.IO.File]::AppendAllText($LogFile, $Text, $utf8NoBom)
}

function Write-LogLine {
    param([string]$Text)

    Append-LogText -Text ($Text + "`r`n")
}

function Remove-StateFiles {
    foreach ($path in @($StateFile, $PidFile)) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Quote-CmdArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -notmatch '[\s"&|<>^]') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

$exitCode = 0

try {
    Write-LogLine -Text "[$(Get-Date -Format s)] Background worker started."
    Write-LogLine -Text "Start script: $StartScript"
    if ($PassThroughArgs.Count -gt 0) {
        Write-LogLine -Text "Arguments: $($PassThroughArgs -join ' ')"
    }
    Write-LogLine -Text ""

    $cmdParts = @(
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $StartScript
    ) + $PassThroughArgs
    $cmdLine = (($cmdParts | ForEach-Object { Quote-CmdArgument -Value $_ }) -join " ") + " 2>&1"

    & cmd.exe /d /c $cmdLine | ForEach-Object {
        $text = $_ | Out-String
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Append-LogText -Text $text
        }
    }

    if ($LASTEXITCODE -is [int]) {
        $exitCode = $LASTEXITCODE
    }
} catch {
    $exitCode = 1
    Write-LogLine -Text "[$(Get-Date -Format s)] Background worker failed."
    Write-LogLine -Text ($_ | Out-String)
} finally {
    Write-LogLine -Text ""
    Write-LogLine -Text "[$(Get-Date -Format s)] Background worker exiting with code $exitCode."
    Remove-StateFiles
}

exit $exitCode
