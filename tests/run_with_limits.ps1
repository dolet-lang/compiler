param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [int]$TimeoutSeconds = 30,
    [int]$MaxWorkingSetMB = 768
)

$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
$process = $null
$limitBytes = [int64]$MaxWorkingSetMB * 1MB
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$failureCode = 0
$failureMessage = ""

try {
    $process = Start-Process -FilePath $Executable -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    while (-not $process.HasExited) {
        $process.Refresh()
        if ($process.WorkingSet64 -gt $limitBytes) {
            $failureCode = 125
            $failureMessage = "memory limit exceeded ($MaxWorkingSetMB MB)"
            break
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            $failureCode = 124
            $failureMessage = "timeout after $TimeoutSeconds seconds"
            break
        }
        Start-Sleep -Milliseconds 100
    }

    if ($failureCode -ne 0 -and -not $process.HasExited) {
        & taskkill.exe /PID $process.Id /T /F *> $null
        $process.WaitForExit()
    } else {
        $process.WaitForExit()
    }

    if (Test-Path -LiteralPath $stdoutPath) {
        Get-Content -LiteralPath $stdoutPath
    }
    if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath | ForEach-Object { [Console]::Error.WriteLine($_) }
    }

    if ($failureCode -ne 0) {
        [Console]::Error.WriteLine("[LIMIT] ${Executable}: $failureMessage")
        exit $failureCode
    }
    exit $process.ExitCode
} finally {
    if ($process -ne $null -and -not $process.HasExited) {
        & taskkill.exe /PID $process.Id /T /F *> $null
    }
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
}
