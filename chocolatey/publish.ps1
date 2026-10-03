<#
.SYNOPSIS
Publishes the Chocolatey `edamame-cli` package for an edamame_cli release, or
retries a publish Chocolatey deferred.

.DESCRIPTION
-Mode Publish (release_others.yml, "Publish to Chocolatey", Windows leg):
stamps the package with the URL and SHA256 of the release's Windows binary,
packs it and pushes it as -ChocoVersion.

  * 409 Conflict means this version is ALREADY published -- and it must NOT be
    treated as success. Rust builds are not bit-reproducible, so a re-run that
    re-uploads the asset produces a DIFFERENT binary with a different SHA256.
    Swallowing the 409 leaves the published package pointing at the new asset
    while still declaring the old checksum. That is exactly how v1.8.0 shipped
    broken:

      release published = 2026-08-18T08:24:44Z
      asset re-uploaded = 2026-08-19T02:19:09Z  (18h later)
      package checksum  = c00641ea...  (first binary)
      actual asset      = 2ed26371...  (re-uploaded binary)

    `choco install edamame-cli` then fails the checksum gate for every user.
    The workflow's check_choco probe cannot prevent this alone: a freshly
    pushed package sits in MODERATION and 404s on community.chocolatey.org, so
    the probe reports "does not exist" while push still returns 409.
    Chocolatey versions are immutable, so on 409 the fix is to publish the NEXT
    revision suffix carrying the correct checksum -- never to pretend the stale
    one is fine.
  * 403 Forbidden while a version of the package is in moderation: Chocolatey
    takes no new version until that one is approved or rejected. When the
    package page shows a version in moderation and the release's Windows
    binary is published, the publish is DEFERRED, never skipped: exit 0 with a
    ::warning::, the job summary, the step output result=deferred and
    <MarkerDir>/chocolatey-deferred.json, the marker edamame_app's
    release_all.sh reads (the workflow uploads it as the chocolatey-deferred
    artifact). chocolatey_deferred.yml retries every day.
  * Anything else fails: another push error, a 403 with no version in
    moderation (a key or ownership problem), a moderation probe that could not
    read the page, or a Windows binary that is not published.

-Mode Retry (chocolatey_deferred.yml, daily): takes the newest edamame_cli
release that carries the Windows binary. When Chocolatey has no package for
it, publishes it as above (not while a release_others.yml run is in
progress). Fails when the push fails, and when Chocolatey has been missing a
release for more than -MaxDeferredDays, counted from the publication of the
oldest release it is missing.

Keep in step with edamame_app tools/chocolatey_publish.ps1 (same logic, its
own package).
#>
[CmdletBinding()]
param(
  [ValidateSet('Publish', 'Retry')]
  [string] $Mode = 'Publish',
  # Publish: the release version (X.Y.Z, tag vX.Y.Z).
  [string] $Version,
  # Publish: the Chocolatey version to push first (X.Y.Z or X.Y.Z.N).
  [string] $ChocoVersion,
  # Publish: push -ChocoVersion as-is and tolerate a 409.
  [switch] $Force,
  # Retry: the age of a deferral that fails the run.
  [int] $MaxDeferredDays = 7,
  # Where chocolatey-deferred.json is written on a deferral.
  [string] $MarkerDir = '.'
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# The package
# --------------------------------------------------------------------------
$PackageId = 'edamame-cli'
$Nuspec = 'chocolatey/edamame-cli.nuspec'
$InstallScript = 'chocolatey/tools/chocolateyInstall.ps1'
$ReleaseRepo = 'edamametechnologies/edamame_cli'
$ReleaseWorkflow = 'release_others.yml'
$RetryWorkflow = 'chocolatey_deferred.yml'
$PackagePage = "https://community.chocolatey.org/packages/$PackageId"

# The asset the package installs.
function Get-PackageAssetName([string] $v) { "edamame_cli-$v-x86_64-pc-windows-msvc.exe" }

# The assets the Windows leg publishes: a deferral is recorded only when all
# of them are on the release.
function Get-ReleaseAssetNames([string] $v) {
  @(Get-PackageAssetName $v)
}

function Get-AssetUrl([string] $v, [string] $name) {
  "https://github.com/$ReleaseRepo/releases/download/v$v/$name"
}

# Stamps everything but the version: the URL and SHA256 of the live asset.
function Set-PackageContent([string] $v) {
  $name = Get-PackageAssetName $v
  $url = Get-AssetUrl $v $name
  Write-Host "Downloading: $url"
  $maxRetries = 5
  $retryDelaySec = 10
  for ($i = 1; $i -le $maxRetries; $i++) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $name -UseBasicParsing
      break
    } catch {
      if ($i -eq $maxRetries) { throw }
      Write-Host "Attempt $i failed, retrying in ${retryDelaySec}s..."
      Start-Sleep -Seconds $retryDelaySec
    }
  }
  $sha = (Get-FileHash -Algorithm SHA256 $name).Hash.ToLower()
  Write-Host "SHA256: $sha"
  # Pin the URL to the BASE version, and match EITHER quote style.
  #
  # The template ships `$url64 = "...v$packageVersion/...-$packageVersion-..."`
  # -- DOUBLE quoted, interpolating $packageVersion. This replace used to
  # anchor on ''.*'' (single quotes only), so it never matched and the
  # rewrite silently no-opped, leaving the interpolating form in place.
  #
  # That is invisible while the Chocolatey version equals the release
  # version, and fatal the moment the revision-suffix path bumps it: the
  # package then resolves to v1.8.2.1/edamame_cli-1.8.2.1-...exe, a tag
  # and asset that never exist, so `choco install` 404s forever on an
  # immutable package. Every revision ever pushed (1.8.1.1, 1.8.2.1) was
  # dead on arrival for this reason.
  #
  # Emit a single-quoted LITERAL so nothing interpolates at install time
  # and the URL always names the base version actually published.
  (Get-Content $InstallScript) -replace '\$url64 = .*', "`$url64 = '$url'" | Set-Content $InstallScript
  (Get-Content $InstallScript) -replace '\$checksum64 = ''.*''', "`$checksum64 = '$sha'" | Set-Content $InstallScript
  $script:PackageSha = $sha
}

function Set-PackageVersion([string] $cv) {
  (Get-Content $Nuspec) -replace '<version>.*</version>', "<version>$cv</version>" | Set-Content $Nuspec
  (Get-Content $InstallScript) -replace '\$packageVersion = ''.*''', "`$packageVersion = '$cv'" | Set-Content $InstallScript
}

# --------------------------------------------------------------------------
# Shared logic (identical in edamame_app tools/chocolatey_publish.ps1)
# --------------------------------------------------------------------------

function Set-StepOutput([string] $name, [string] $value) {
  if ($env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "$name=$value" }
}

function Add-StepSummary([string[]] $lines) {
  if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $lines }
}

# X.Y.Z of a Chocolatey version (X.Y.Z or X.Y.Z.N).
function Get-BaseVersion([string] $v) {
  $parts = $v.Split('.')
  if ($parts.Count -lt 3) { return [version]"$v.0" }
  [version]("{0}.{1}.{2}" -f $parts[0], $parts[1], $parts[2])
}

# The package page's version history: one row per version with its moderation
# status ("Approved", "Pending Automated Review", "Waiting for Maintainer",
# ...). Throws when the page cannot be read: a failed lookup is never "no
# version in moderation".
function Get-ChocoFeed {
  $html = (Invoke-WebRequest -Uri $PackagePage -UseBasicParsing -ErrorAction Stop).Content
  $rows = @()
  $at = $html.IndexOf('id="versionhistory"')
  if ($at -ge 0) {
    $section = $html.Substring($at)
    $end = $section.IndexOf('</table>')
    if ($end -ge 0) { $section = $section.Substring(0, $end) }
    foreach ($m in [regex]::Matches($section, '(?s)<tr[^>]*>(.*?)</tr>')) {
      $row = $m.Groups[1].Value
      $v = [regex]::Match($row, '(?s)<td class="version"[^>]*>.*?<span>\s*([0-9]+(?:\.[0-9]+)+)\s*</span>')
      if (-not $v.Success) { continue }
      $cells = [regex]::Matches($row, '(?s)<td[^>]*>(.*?)</td>')
      $status = ''
      if ($cells.Count -gt 0) {
        $status = (([regex]::Replace($cells[$cells.Count - 1].Groups[1].Value, '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
      }
      $rows += [pscustomobject]@{ Version = $v.Groups[1].Value; Status = $status }
    }
  }
  [pscustomobject]@{
    AwaitingModeration = ($html -match 'versions of this package awaiting moderation')
    Versions           = $rows
  }
}

# Versions neither approved nor rejected: in moderation.
function Get-InModeration($feed) {
  @($feed.Versions | Where-Object { $_.Status -notmatch '^(Approved|Rejected)\b' })
}

function Get-MissingReleaseAssets([string] $v) {
  $missing = @()
  foreach ($name in (Get-ReleaseAssetNames $v)) {
    $found = $false
    for ($i = 1; $i -le 3 -and -not $found; $i++) {
      try {
        $null = Invoke-WebRequest -Uri (Get-AssetUrl $v $name) -Method Head -UseBasicParsing -ErrorAction Stop
        $found = $true
      } catch {
        if ($i -lt 3) { Start-Sleep -Seconds 5 }
      }
    }
    if (-not $found) { $missing += $name }
  }
  $missing
}

# Records a deferred publish: the marker, the warning, the job summary.
function Write-Deferral([string] $base, [string] $cv, $blockers) {
  $missing = @(Get-MissingReleaseAssets $base)
  if ($missing.Count -gt 0) {
    Write-Host "ERROR: Chocolatey refused the push while a version is in moderation, but release v$base lacks $($missing -join ', '): not recording a deferral."
    exit 1
  }
  $blockedBy = @($blockers | ForEach-Object { "$($_.Version) ($($_.Status))" })
  if ($blockedBy.Count -eq 0) { $blockedBy = @('a version in moderation (see the package page)') }
  $marker = [ordered]@{
    package        = $PackageId
    version        = $base
    choco_version  = $cv
    release_repo   = $ReleaseRepo
    release_tag    = "v$base"
    release_assets = @(Get-ReleaseAssetNames $base)
    blocked_by     = @($blockers | ForEach-Object { [ordered]@{ version = $_.Version; status = $_.Status } })
    package_page   = $PackagePage
    retry_workflow = $RetryWorkflow
    recorded_at    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  New-Item -ItemType Directory -Force -Path $MarkerDir | Out-Null
  $markerPath = Join-Path $MarkerDir 'chocolatey-deferred.json'
  $marker | ConvertTo-Json -Depth 5 | Set-Content -Path $markerPath -Encoding utf8
  Write-Host "::warning title=Chocolatey publish DEFERRED::$PackageId $cv was not published: Chocolatey takes no new version while $($blockedBy -join ', ') is in moderation. The release assets of v$base are published. $RetryWorkflow retries daily and fails once Chocolatey has missed a release for $MaxDeferredDays days. $PackagePage"
  Add-StepSummary @(
    "## Chocolatey publish DEFERRED",
    "",
    "``$PackageId`` $cv was **not** published: Chocolatey refused the push (403) while a version of the package is in moderation, and takes no new version until that one is approved or rejected.",
    "",
    "| In moderation | Status |",
    "|---|---|"
  )
  if (@($blockers).Count -gt 0) {
    Add-StepSummary @($blockers | ForEach-Object { "| $($_.Version) | $($_.Status) |" })
  } else {
    Add-StepSummary @("| (see the package page) | awaiting moderation |")
  }
  Add-StepSummary @(
    "",
    "The release assets of v$base are published ($((Get-ReleaseAssetNames $base) -join ', ')). ``$RetryWorkflow`` retries the push daily and fails once Chocolatey has missed a release for more than $MaxDeferredDays days. Package page: $PackagePage"
  )
  Write-Host "Deferral recorded in $markerPath"
}

# Packs and pushes, from -ChocoVersion on. Returns 'published' or 'deferred';
# exits non-zero on anything else.
function Publish-Package([string] $base, [string] $cv, [bool] $force) {
  if (-not $env:CHOCOLATEY_API_KEY) {
    # A release on main without the key is a broken publish, not a skip: the
    # app package went unpublished from 1.1.2 to 2.0.2 behind a green
    # "Skipping" line (the org secret was not shared with edamame_app).
    Write-Host "ERROR: CHOCOLATEY_API_KEY is not available to this repository; the Chocolatey package was not published"
    exit 1
  }
  Write-Host "Release version: $base / Chocolatey version: $cv"
  Set-PackageContent $base
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Set-PackageVersion $cv

    Write-Host "Packing Chocolatey package ${cv}..."
    choco pack $Nuspec | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-Host "ERROR: choco pack failed with exit code $LASTEXITCODE"
      exit $LASTEXITCODE
    }

    Write-Host "Pushing to Chocolatey ${cv}..."
    $pushOut = choco push "$PackageId.$cv.nupkg" -s https://push.chocolatey.org/ -k $env:CHOCOLATEY_API_KEY --verbose 2>&1 | Out-String
    $pushRc = $LASTEXITCODE
    Write-Host $pushOut
    if ($pushRc -eq 0) {
      Write-Host "Chocolatey package $cv published (checksum $script:PackageSha)."
      $script:PublishedVersion = $cv
      return 'published'
    }

    if ($pushOut -match '409 \(Conflict\)' -or $pushOut -match 'already exists' -or $pushOut -match 'SkipDuplicate') {
      if ($force) {
        Write-Host "INFO: force_choco_version: $cv is already on the feed and stays as it is (409 tolerated)."
        $script:PublishedVersion = $cv
        return 'published'
      }
      $nextRev = 1
      if ($cv -match "^$([regex]::Escape($base))\.(\d+)$") { $nextRev = [int]$Matches[1] + 1 }
      $cv = "$base.$nextRev"
      Write-Host "INFO: version already on the feed; retrying as $cv so the live checksum matches the live asset."
      continue
    }

    if ($pushOut -match '403 \(Forbidden\)' -or $pushOut -match 'success: 403\b') {
      # Chocolatey answers 403 to a push while an earlier version of the
      # package is in moderation; the client prints no reason. Confirm it on
      # the package page before calling it a deferral.
      try {
        $feed = Get-ChocoFeed
      } catch {
        Write-Host "ERROR: Chocolatey refused the push (403) and the moderation check of $PackagePage failed: $($_.Exception.Message)"
        exit $pushRc
      }
      $blockers = Get-InModeration $feed
      if ($blockers.Count -eq 0 -and -not $feed.AwaitingModeration) {
        Write-Host "ERROR: Chocolatey refused the push (403) and no version of $PackageId is in moderation ($PackagePage): not a moderation deferral. Check the API key and the package's maintainers."
        exit $pushRc
      }
      Write-Host "Chocolatey refused $cv while a version is in moderation: $(@($blockers | ForEach-Object { "$($_.Version) ($($_.Status))" }) -join ', ')"
      Write-Deferral $base $cv $blockers
      return 'deferred'
    }

    Write-Host "ERROR: choco push failed with exit code $pushRc"
    exit $pushRc
  }
  Write-Host "ERROR: exhausted revision suffixes without publishing a package matching the current asset."
  Write-Host "ERROR: refusing to report success while the live package is out of sync with the release asset."
  exit 1
}

function Invoke-Publish {
  if (-not $Version -or -not $ChocoVersion) { throw '-Version and -ChocoVersion are required with -Mode Publish' }
  $result = Publish-Package $Version $ChocoVersion ([bool]$Force)
  Set-StepOutput 'result' $result
  if ($result -eq 'published') {
    Set-StepOutput 'choco_version' $script:PublishedVersion
  }
  exit 0
}

function Invoke-Retry {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $json = gh api "repos/$ReleaseRepo/releases?per_page=30" --jq '[.[] | select(.draft == false and .prerelease == false) | {tag: .tag_name, published: (.published_at | fromdateiso8601), assets: [.assets[].name]}]'
  if ($LASTEXITCODE -ne 0 -or -not $json) { throw "listing the releases of $ReleaseRepo failed" }
  # Releases that carry the package's asset (a per-OS release may not).
  $parsed = ($json -join "`n") | ConvertFrom-Json
  $releases = @(@(foreach ($r in $parsed) {
        if ($r.tag -notmatch '^v\d+\.\d+\.\d+$') { continue }
        $v = $r.tag.Substring(1)
        if (@($r.assets) -contains (Get-PackageAssetName $v)) {
          [pscustomobject]@{ Version = $v; Base = [version]$v; Published = [int64]$r.published }
        }
      }) | Sort-Object Base -Descending)
  if ($releases.Count -eq 0) { throw "no release of $ReleaseRepo carries the package asset" }
  $target = $releases[0]

  $feed = Get-ChocoFeed
  if (@($feed.Versions).Count -eq 0) { throw "could not read the version history of $PackagePage" }
  $live = @($feed.Versions | Where-Object { $_.Status -notmatch '^Rejected\b' })
  $newestOnFeed = [version]'0.0.0'
  foreach ($row in $live) {
    $b = Get-BaseVersion $row.Version
    if ($b -gt $newestOnFeed) { $newestOnFeed = $b }
  }
  foreach ($row in (Get-InModeration $feed)) {
    if ($row.Status -match 'Waiting for Maintainer') {
      Write-Host "::warning title=Chocolatey package needs its maintainer::$PackageId $($row.Version) is waiting for the maintainer: Chocolatey's checks asked for a change, it will not be approved without one, and it blocks every new version. $PackagePage/$($row.Version)"
    }
  }

  $onFeed = @($live | Where-Object { (Get-BaseVersion $_.Version) -eq $target.Base })
  if ($onFeed.Count -gt 0) {
    $states = ($onFeed | ForEach-Object { "$($_.Version) ($($_.Status))" }) -join ', '
    Write-Host "Chocolatey has $PackageId for the latest release v$($target.Version): $states. Nothing deferred."
    Add-StepSummary @("## Chocolatey: nothing deferred", "", "``$PackageId`` for v$($target.Version) is on the feed: $states.")
    Set-StepOutput 'result' 'current'
    exit 0
  }

  $missing = @($releases | Where-Object { $_.Base -gt $newestOnFeed })
  if ($missing.Count -eq 0) { $missing = @($target) }
  $since = ($missing | Measure-Object -Property Published -Minimum).Minimum
  $ageDays = [math]::Round(($now - $since) / 86400.0, 1)
  Write-Host "Chocolatey lacks $PackageId for v$($target.Version) (newest on the feed: $newestOnFeed); missing releases since $([DateTimeOffset]::FromUnixTimeSeconds($since).ToString('yyyy-MM-dd HH:mm')) UTC, $ageDays days."

  $result = 'skipped'
  $running = gh run list --repo $env:GITHUB_REPOSITORY --workflow $ReleaseWorkflow --limit 20 --json status --jq '[.[] | select(.status != "completed")] | length'
  if ($LASTEXITCODE -ne 0) { throw "listing the $ReleaseWorkflow runs failed" }
  if ([int]$running -gt 0) {
    Write-Host "::notice::A $ReleaseWorkflow run is in progress: it publishes to Chocolatey itself; no push from here."
  } else {
    $result = Publish-Package $target.Version $target.Version $false
  }
  Set-StepOutput 'result' $result
  if ($result -eq 'published') {
    Write-Host "::notice title=Deferred Chocolatey publish done::$PackageId $script:PublishedVersion published for v$($target.Version)."
    Add-StepSummary @("## Chocolatey: deferred publish done", "", "``$PackageId`` $script:PublishedVersion published for v$($target.Version) (Chocolatey moderates it before listing it).")
    exit 0
  }
  if ($ageDays -gt $MaxDeferredDays) {
    Write-Host "::error title=Chocolatey publish deferred too long::Chocolatey has missed $PackageId releases for $ageDays days (limit $MaxDeferredDays): users of choco install do not get v$($target.Version). Resolve the version in moderation on $PackagePage (or have it rejected), then re-run $RetryWorkflow."
    Add-StepSummary @("", "**Deferred for $ageDays days, over the $MaxDeferredDays-day limit.**")
    exit 1
  }
  Write-Host "Deferred for $ageDays days (limit $MaxDeferredDays); retried again tomorrow."
  exit 0
}

if ($Mode -eq 'Publish') { Invoke-Publish } else { Invoke-Retry }
