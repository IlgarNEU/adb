# =============================================================================
#  photo_upload.ps1 — Continuous photo uploader → Google Drive (Windows)
# =============================================================================
#
#  SETUP (one-time):
#    1. Install rclone:         winget install Rclone.Rclone
#       Or download from:       https://rclone.org/downloads/
#    2. Configure Google Drive: rclone config
#       → Name the remote "gdrive" (or change $RcloneRemote below)
#    3. Allow script execution (run PowerShell as Administrator, once):
#           Set-ExecutionPolicy RemoteSigned
#    4. Run:
#           .\photo_upload.ps1
#
# =============================================================================

# ── Configuration ─────────────────────────────────────────────────────────────

$RcloneRemote   = "gdrive"

$PhotosDir      = "$HOME\photos"
$PhotosArchive  = "$HOME\uploaded_archive\photos"
$GdrivePhotos   = "${RcloneRemote}:AutoUpload/photos"

$ScanInterval   = 10      # seconds between scans
$MinAge         = 30      # seconds — skip files newer than this (may still be writing)

$LogFile        = "$HOME\photo_upload.log"
$MaxLogLines    = 5000

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Invoke-LogRotate {
    if (-not (Test-Path $LogFile)) { return }
    $lines = Get-Content $LogFile
    if ($lines.Count -gt $MaxLogLines) {
        $lines | Select-Object -Last ($MaxLogLines / 2) | Set-Content $LogFile
        Write-Log "Log rotated (was $($lines.Count) lines)."
    }
}

function Is-OldEnough {
    param([System.IO.FileInfo]$File)
    $age = (Get-Date) - $File.LastWriteTime
    return $age.TotalSeconds -ge $MinAge
}

function Upload-AndArchive {
    param([System.IO.FileInfo]$File)

    Write-Log "↑ Uploading: $($File.Name)"

    $result = & rclone copy $File.FullName $GdrivePhotos `
        --transfers 4 `
        --retries 5 `
        --low-level-retries 10 `
        --stats 0 `
        --log-level ERROR 2>&1

    if ($LASTEXITCODE -eq 0) {
        $dest = Join-Path $PhotosArchive $File.Name
        Move-Item -Path $File.FullName -Destination $dest -Force
        Write-Log "✔ Archived: $($File.Name)"
    } else {
        Write-Log "✖ Upload FAILED: $($File.Name) (will retry next cycle)"
        if ($result) { Write-Log "   rclone error: $result" }
    }
}

# ── Init ──────────────────────────────────────────────────────────────────────

New-Item -ItemType Directory -Force -Path $PhotosArchive | Out-Null
if (-not (Test-Path $LogFile)) { New-Item -ItemType File -Path $LogFile | Out-Null }

Write-Log "════════════════════════════════════════════════════════"
Write-Log "  photo_upload.ps1 started (PID $PID)"
Write-Log "  Source  : $PhotosDir"
Write-Log "  Drive   : $GdrivePhotos"
Write-Log "  Archive : $PhotosArchive"
Write-Log "════════════════════════════════════════════════════════"

# Verify rclone is accessible
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: rclone not found. Install it with: winget install Rclone.Rclone"
    exit 1
}

# Verify remote exists
$remotes = & rclone listremotes 2>&1
if ($remotes -notmatch "^${RcloneRemote}:") {
    Write-Log "ERROR: rclone remote '$RcloneRemote' not found."
    Write-Log "Run: rclone config   (create a remote named '$RcloneRemote')"
    exit 1
}

# Verify photos folder exists
if (-not (Test-Path $PhotosDir)) {
    Write-Log "ERROR: Photos folder not found: $PhotosDir"
    exit 1
}

# ── Main loop ─────────────────────────────────────────────────────────────────

while ($true) {
    Invoke-LogRotate

    $uploaded = 0
    $photos = Get-ChildItem -Path $PhotosDir -File | Where-Object { $_.Name -notlike ".*" }

    foreach ($photo in $photos) {
        if (Is-OldEnough $photo) {
            Upload-AndArchive $photo
            $uploaded++
        }
    }

    if ($uploaded -eq 0) {
        Write-Log "No new photos."
    }

    Start-Sleep -Seconds $ScanInterval
}
