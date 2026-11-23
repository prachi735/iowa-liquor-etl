# First run on Windows. From the repo folder:
#   powershell -ExecutionPolicy Bypass -File scripts\first_run.ps1
# Creates .venv, installs packages, builds the database, loads the sample file in data\,
# transforms it, shows the status and runs the tests. Everything is also written to
# first_run.log. The PostgreSQL password is asked for here (not stored) unless .env has one.

$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)
$log = Join-Path (Get-Location) "first_run.log"
"First run $(Get-Date -Format s)" | Out-File $log -Encoding utf8
$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"

function Step($title, [scriptblock]$command) {
    "`n=== $title ===" | Tee-Object -FilePath $log -Append
    & $command 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log -Append
    if ($LASTEXITCODE -ne 0) {
        "*** $title failed (exit code $LASTEXITCODE). Stopping here; see first_run.log." |
            Tee-Object -FilePath $log -Append
        exit 1
    }
}

if (-not (Test-Path .env)) { Copy-Item .env.example .env }
$hasPassword = Select-String -Path .env -Pattern '^\s*PGPASSWORD\s*=\s*\S' -Quiet
if (-not $env:PGPASSWORD -and -not $hasPassword) {
    $secure = Read-Host "PostgreSQL password for the user in .env (postgres)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if (Get-Command py -ErrorAction SilentlyContinue) { $base = "py" } else { $base = "python" }
$python = ".\.venv\Scripts\python.exe"

Step "Python version" { & $base --version }
if (-not (Test-Path $python)) { Step "Create .venv" { & $base -m venv .venv } }
Step "Install packages" { & $python -m pip install --disable-pip-version-check -q -r requirements.txt }

$sample = Get-ChildItem data -Include *.zip, *.csv -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\landing\\' } | Select-Object -First 1

Step "Setup database" { & $python -m pipeline setup }
if ($sample) {
    Step "Load $($sample.Name)" { & $python -m pipeline load $sample.FullName }
} else {
    "`nNo sample file found in data\ - skipping the load." | Tee-Object -FilePath $log -Append
}
Step "Transform" { & $python -m pipeline transform }
Step "Status" { & $python -m pipeline status }
Step "Tests" { & $python -m pytest -q }

"`nAll steps finished. Log: $log" | Tee-Object -FilePath $log -Append
