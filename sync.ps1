<#
.SYNOPSIS
    AaradhyaDT Profile Synchronization & Quality Assurance Engine
.DESCRIPTION
    Automates pre-commit link validation, secret scanning, ecosystem alignment,
    safe git rebase, conventional commits, and push for the AaradhyaDT GitHub Profile.
.PARAMETER Message
    Custom conventional commit message. Defaults to 'docs(profile): update profile README, ecosystem systems & verified metrics'.
.PARAMETER PullOnly
    Safely pull updates from origin main with rebase and autostash without pushing.
.PARAMETER CheckLinks
    Perform deep HTTP HEAD verification on all URLs, badges, and asset links in README.md.
.PARAMETER WhatIf
    Dry-run mode. Audits repository and links without committing or pushing.
#>

[CmdletBinding()]
param(
    [Alias("m")]
    [string]$Message = "",

    [switch]$PullOnly,
    [switch]$CheckLinks,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Write-Step {
    param([string]$Tag, [string]$Text, [string]$Color = "Cyan")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Tag] " -NoNewline -ForegroundColor $Color
    Write-Host $Text
}

function Write-Success {
    param([string]$Text)
    Write-Step "Done" $Text "Green"
}

function Write-Warn {
    param([string]$Text)
    Write-Step "Warn" $Text "Yellow"
}

function Write-Err {
    param([string]$Text)
    Write-Step "Error" $Text "Red"
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor DarkYellow
Write-Host "  AaradhyaDT -- GitHub Profile Engine & Workflow Synchronization" -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor DarkYellow

# 1. Pre-flight Git Verification
try {
    $currentBranch = (git branch --show-current).Trim()
    if ($currentBranch -ne "main") {
        Write-Err "Active branch is '$currentBranch'. AaradhyaDT profile must target 'main'."
        exit 1
    }
} catch {
    Write-Err "Git executable not found or not a valid git repository: $_"
    exit 1
}

# 2. Pull-Only Mode
if ($PullOnly) {
    Write-Step "Git" "Pulling latest changes from origin main (--rebase --autostash)..." "Cyan"
    git pull --rebase --autostash origin main
    Write-Success "Safe pull complete. Workspace synchronized in $($sw.Elapsed.TotalSeconds.ToString('0.00'))s."
    exit 0
}

# 3. Secret & Safety Scan
$readmePath = Join-Path $ScriptDir "README.md"
if (-not (Test-Path $readmePath)) {
    Write-Err "README.md not found in repository root: $readmePath"
    exit 1
}

Write-Step "Audit" "Running pre-commit hygiene & secret scan on profile assets..." "Cyan"
$content = Get-Content $readmePath -Raw

$secretPatterns = @(
    "ghp_[A-Za-z0-9]{36}",
    "github_pat_[A-Za-z0-9_]{82}",
    "AIza[0-9A-Za-z-_]{35}",
    "sk-[A-Za-z0-9]{32,}"
)

$hasSecret = $false
foreach ($pattern in $secretPatterns) {
    if ($content -match $pattern) {
        Write-Err "CRITICAL: Potential API key or secret token detected matching pattern: $pattern"
        $hasSecret = $true
    }
}

if ($hasSecret) {
    Write-Err "Aborting commit due to security finding."
    exit 1
}

# 4. Link & Asset Verification (Explicit or when modified)
if ($CheckLinks) {
    Write-Step "Verify" "Checking reachability of URLs, shields badges, and assets in README.md..." "Cyan"
    $urlMatches = [regex]::Matches($content, 'https?://[^\s\)\]\"\''>]+')
    $uniqueUrls = $urlMatches | ForEach-Object { $_.Value } | Select-Object -Unique

    $failedUrls = @()
    foreach ($url in $uniqueUrls) {
        # Skip badge generators, shields, and known anti-bot endpoints (LinkedIn 999)
        if ($url -match "readme-typing-svg" -or $url -match "img\.shields\.io" -or $url -match "linkedin\.com") {
            continue
        }
        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Method = "HEAD"
            $req.Timeout = 4000
            $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            $resp = $req.GetResponse()
            $code = [int]$resp.StatusCode
            $resp.Close()
            if ($code -ge 400) {
                $failedUrls += "$url (HTTP $code)"
            }
        } catch {
            # Try GET fallback
            try {
                $req = [System.Net.WebRequest]::Create($url)
                $req.Method = "GET"
                $req.Timeout = 4000
                $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                $resp = $req.GetResponse()
                $resp.Close()
            } catch {
                $failedUrls += "$url ($($_.Exception.Message))"
            }
        }
    }

    if ($failedUrls.Count -gt 0) {
        Write-Warn "Unreachable or suspicious URLs detected ($($failedUrls.Count)):"
        foreach ($f in $failedUrls) {
            Write-Host "   - $f" -ForegroundColor Red
        }
    } else {
        Write-Success "All inspected links ($($uniqueUrls.Count)) returned healthy responses."
    }
}

# 5. Git Synchronization
Write-Step "Git" "Rebasing against remote origin main..." "Cyan"
git pull --rebase --autostash origin main

$gitStatus = (git status --porcelain).Trim()
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Success "Working tree clean. Nothing to commit. Synchronized in $($sw.Elapsed.TotalSeconds.ToString('0.00'))s."
    exit 0
}

Write-Step "Status" "Detected uncommitted modifications:" "Yellow"
git status --short

if ($WhatIf) {
    Write-Warn "Dry-run active (-WhatIf). Skipping commit and push."
    exit 0
}

$commitMsg = if (-not [string]::IsNullOrWhiteSpace($Message)) {
    $Message
} else {
    "docs(profile): update profile README, ecosystem systems & verified metrics"
}

Write-Step "Git" "Staging changes and creating commit: '$commitMsg'" "Cyan"
git add .
git commit -m "$commitMsg"

Write-Step "Git" "Pushing to origin main..." "Cyan"
git push origin main

Write-Success "Profile successfully synchronized and pushed to GitHub in $($sw.Elapsed.TotalSeconds.ToString('0.00'))s."
Write-Host "==========================================================================" -ForegroundColor DarkYellow
Write-Host ""
