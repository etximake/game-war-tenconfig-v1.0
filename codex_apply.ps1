# codex_apply.ps1
# Usage:
#   1) Copy git apply in Codex (patch is in clipboard)
#   2) In repo root: powershell -ExecutionPolicy Bypass -File .\codex_apply.ps1

$ErrorActionPreference = "Stop"

# Ensure we're in a git repo
$top = (git rev-parse --show-toplevel 2>$null)
if (-not $top) { throw "Not a git repo. Please cd into your repo first." }
Set-Location $top

# Read patch from clipboard
$patch = Get-Clipboard -Raw
if ([string]::IsNullOrWhiteSpace($patch)) { throw "Clipboard is empty. Copy 'Copy git apply' again." }

# Save to temp file
$tmp = Join-Path $env:TEMP ("codex_patch_" + [guid]::NewGuid().ToString() + ".patch")
Set-Content -Path $tmp -Value $patch -Encoding UTF8

Write-Host "Repo: $top" -ForegroundColor Cyan
Write-Host ("Branch: " + (git branch --show-current)) -ForegroundColor Cyan

Write-Host "`n--- Patch preview (stat) ---" -ForegroundColor Yellow
git apply --stat $tmp

Write-Host "`n--- Checking patch can apply ---" -ForegroundColor Yellow
git apply --check --whitespace=nowarn --recount $tmp

Write-Host "`n--- Applying patch ---" -ForegroundColor Yellow
git apply --whitespace=nowarn --recount $tmp

Write-Host "`n✅ Applied. Changed files:" -ForegroundColor Green
git diff --name-status

# If nothing changed, tell user where to look
$changed = (git diff --name-only)
if (-not $changed) {
  Write-Host "`n⚠️ No working-tree diff detected." -ForegroundColor DarkYellow
  Write-Host "Check staged diff (maybe applied with --cached somewhere):" -ForegroundColor DarkYellow
  git diff --cached --name-status
}

# Optional: open changed files in VS Code if installed
if ($changed) {
  Write-Host "`nOpen changed files in VS Code? (y/N)" -ForegroundColor Cyan
  $ans = Read-Host
  if ($ans -match '^(y|Y)$') { code $changed }
}

Remove-Item $tmp -Force