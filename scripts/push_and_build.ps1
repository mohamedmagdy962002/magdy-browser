<#
  Pushes the Magdy Browser project to GitHub and opens the cloud macOS build.

  Usage (PowerShell):
    .\scripts\push_and_build.ps1 -RepoUrl https://github.com/<you>/magdy-browser.git

  You will be asked for your GitHub username and a Personal Access Token
  (password field) the first time. Create one at:
    https://github.com/settings/tokens  ->  scope: repo (public_repo is enough)
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoUrl
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path ".git")) {
    git init -b main
}

$remote = git remote 2>$null
if ($remote -contains "origin") {
    git remote set-url origin $RepoUrl
} else {
    git remote add origin $RepoUrl
}

git add -A
git commit -m "Magdy Browser: update" 2>$null | Out-Null
git push -u origin main

$owner = ($RepoUrl -replace '.*github\.com[:/]', '' -replace '\.git$', '' -split '/')[0]
$repo = ($RepoUrl -replace '.*github\.com[:/]', '' -replace '\.git$', '' -split '/')[1]
$actionsUrl = "https://github.com/$owner/$repo/actions"

Write-Host ""
Write-Host "Pushed. The macOS build starts automatically." -ForegroundColor Green
Write-Host "Watch it here: $actionsUrl"
Write-Host ""
Write-Host "When the 'Build IPA' run finishes:" -ForegroundColor Cyan
Write-Host "  1. Open the run, scroll to 'Upload artifact', download MagdyBrowser-ipa"
Write-Host "  2. Unzip it -> MagdyBrowser-unsigned.ipa"
Write-Host "  3. Sideload it (Windows): https://sideloadly.io  (plug in iPhone, enter Apple ID, Start)"
Write-Host ""

Start-Process $actionsUrl
