param(
    [Parameter(Position = 0)]
    [string] $OutputDirectory,
    [switch] $AllowDirty,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramName = 'build-windows-distribution'
$RequiredRacketBanner = 'Welcome to Racket v9.3 [cs].'
$RequiredRacketVersion = '9.3'
$TargetIdentifier = 'windows-x86_64'
$ApprovedNoticeSha256 = '516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad'
$Usage = @'
Usage:
  tooling/build-windows-distribution.ps1 [-AllowDirty] OUTPUT_DIRECTORY

Build the final native Windows x86-64 release archive with
Racket CS 9.3. The output directory must already exist outside the source
checkout and must not contain the versioned archive or SHA256SUMS.
'@

function Fail([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

function Test-DotenvName([string] $Name) {
    return $Name -match '(?i)(^|[.])env($|[.])'
}

function Get-FullPath([string] $Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Test-PathWithin([string] $Candidate, [string] $Parent) {
    $candidateFull = Get-FullPath $Candidate
    $parentFull = Get-FullPath $Parent
    if ($candidateFull.Equals($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $candidateFull.StartsWith(
        $parentFull + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)
}

function Get-SafeTreeEntries {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [switch] $SkipCompiled,
        [switch] $RejectDotenv
    )

    $rootFull = Get-FullPath $Root
    $pending = [Collections.Generic.Stack[string]]::new()
    $entries = [Collections.Generic.List[object]]::new()
    $pending.Push($rootFull)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
            $name = [IO.Path]::GetFileName($path)
            if (Test-DotenvName $name) {
                if ($RejectDotenv) {
                    Fail "tree contains a forbidden dotenv path: $name"
                }
                continue
            }
            $attributes = [IO.File]::GetAttributes($path)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Fail "tree contains a reparse point: $path"
            }
            $isDirectory = (($attributes -band [IO.FileAttributes]::Directory) -ne 0)
            if ($isDirectory -and $SkipCompiled -and $name -ceq 'compiled') {
                continue
            }
            $entry = [PSCustomObject]@{
                FullPath = Get-FullPath $path
                RelativePath = [IO.Path]::GetRelativePath($rootFull, $path).Replace('\', '/')
                IsDirectory = $isDirectory
            }
            $entries.Add($entry)
            if ($isDirectory) {
                $pending.Push($entry.FullPath)
            }
        }
    }
    return $entries.ToArray() | Sort-Object -Property RelativePath -CaseSensitive
}

function Assert-RegularNonsymlinkFile([string] $Path, [string] $Label) {
    if (-not [IO.File]::Exists($Path)) {
        Fail "$Label must be a regular nonsymlink file"
    }
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail "$Label must be a regular nonsymlink file"
    }
}

function Copy-RegularFile([string] $Source, [string] $Destination, [string] $Label) {
    Assert-RegularNonsymlinkFile $Source $Label
    $parent = [IO.Path]::GetDirectoryName($Destination)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.File]::Copy($Source, $Destination, $false)
}

function Write-LfUtf8([string] $Path, [string] $Content) {
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Get-Sha256([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $hash = [Security.Cryptography.SHA256]::HashData($stream)
        return [Convert]::ToHexString($hash).ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-NativeChecked([string] $Executable, [string[]] $Arguments, [string] $Label) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "$Label failed with status $LASTEXITCODE"
    }
}

function Get-PeMachine([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        try {
            if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
                Fail "runtime file is not a PE image: $Path"
            }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or ($peOffset + 6) -gt $stream.Length) {
                Fail "runtime file has an invalid PE header offset: $Path"
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                Fail "runtime file has an invalid PE signature: $Path"
            }
            return $reader.ReadUInt16()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Find-Dumpbin {
    $command = Get-Command dumpbin.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $vswhere = [IO.Path]::Combine($programFilesX86, 'Microsoft Visual Studio', 'Installer', 'vswhere.exe')
    Assert-RegularNonsymlinkFile $vswhere 'Visual Studio vswhere.exe'
    $installationPath = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installationPath)) {
        Fail 'Visual Studio x64 build tools are unavailable'
    }
    $msvcRoot = [IO.Path]::Combine($installationPath.Trim(), 'VC', 'Tools', 'MSVC')
    if (-not [IO.Directory]::Exists($msvcRoot)) {
        Fail 'Visual Studio MSVC tool directory is unavailable'
    }
    $versions = @(
        [IO.Directory]::EnumerateDirectories($msvcRoot) |
            Where-Object { -not (Test-DotenvName ([IO.Path]::GetFileName($_))) } |
            Sort-Object -Descending
    )
    foreach ($versionDirectory in $versions) {
        $candidate = [IO.Path]::Combine($versionDirectory, 'bin', 'Hostx64', 'x64', 'dumpbin.exe')
        if ([IO.File]::Exists($candidate)) {
            Assert-RegularNonsymlinkFile $candidate 'Visual Studio dumpbin.exe'
            return $candidate
        }
    }
    Fail 'Visual Studio x64 dumpbin.exe is unavailable'
}

function Get-PeDependencies([string] $Dumpbin, [string] $Path) {
    $output = @(& $Dumpbin /NOLOGO /DEPENDENTS $Path 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Fail "dumpbin dependency inspection failed for $Path"
    }
    $dependencies = @(
        $output |
            ForEach-Object { ([string] $_).Trim() } |
            Where-Object { $_ -match '(?i)^[a-z0-9_.-]+[.]dll$' } |
            Sort-Object -Unique
    )
    if ($dependencies.Count -eq 0) {
        Fail "PE dependency inventory is empty for $Path"
    }
    return $dependencies
}

function Assert-NoForbiddenBuildPaths([string[]] $Files, [string[]] $ForbiddenPaths) {
    foreach ($file in $Files) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $latin = [Text.Encoding]::Latin1.GetString($bytes)
        $utf16 = [Text.Encoding]::Unicode.GetString($bytes)
        foreach ($forbiddenPath in $ForbiddenPaths) {
            if ([string]::IsNullOrWhiteSpace($forbiddenPath)) {
                continue
            }
            if ($latin.Contains($forbiddenPath, [StringComparison]::OrdinalIgnoreCase) -or
                $utf16.Contains($forbiddenPath, [StringComparison]::OrdinalIgnoreCase)) {
                Fail 'artifact retains a forbidden checkout, package-registry, or build path'
            }
        }
    }
}

function New-DeterministicZip([string] $ArtifactParent, [string] $ArtifactRootName, [string] $Destination) {
    Add-Type -AssemblyName System.IO.Compression
    $artifactRoot = [IO.Path]::Combine($ArtifactParent, $ArtifactRootName)
    $entries = @(Get-SafeTreeEntries -Root $artifactRoot -RejectDotenv)
    $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $fixedTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $rootEntry = $archive.CreateEntry("$ArtifactRootName/", [IO.Compression.CompressionLevel]::NoCompression)
            $rootEntry.LastWriteTime = $fixedTime
            $rootEntry.ExternalAttributes = 0x10
            foreach ($entry in $entries) {
                $archiveName = "$ArtifactRootName/$($entry.RelativePath)"
                if ($entry.IsDirectory) {
                    $zipEntry = $archive.CreateEntry("$archiveName/", [IO.Compression.CompressionLevel]::NoCompression)
                    $zipEntry.LastWriteTime = $fixedTime
                    $zipEntry.ExternalAttributes = 0x10
                    continue
                }
                $zipEntry = $archive.CreateEntry($archiveName, [IO.Compression.CompressionLevel]::Optimal)
                $zipEntry.LastWriteTime = $fixedTime
                $zipEntry.ExternalAttributes = 0
                $input = [IO.File]::OpenRead($entry.FullPath)
                $output = $zipEntry.Open()
                try {
                    $input.CopyTo($output)
                }
                finally {
                    $output.Dispose()
                    $input.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

if ($Help) {
    [Console]::Out.Write($Usage)
    exit 0
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    [Console]::Error.Write($Usage)
    exit 2
}

$ProjectRoot = Get-FullPath ([IO.Path]::Combine($PSScriptRoot, '..'))
$BuildTempRoot = $null
$StagedArchive = $null
$StagedChecksum = $null
$ArchivePath = $null
$ChecksumPath = $null
$ArchiveCreated = $false
$ChecksumCreated = $false
$OutputsComplete = $false
$Succeeded = $false
$SavedEnvironment = @{}
$EnvironmentChanged = $false

try {
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess -or
        [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
        Fail 'target requires native Windows x86-64'
    }

    if (-not [IO.Directory]::Exists($OutputDirectory)) {
        Fail 'OUTPUT_DIRECTORY must already be a nonsymlink directory'
    }
    $outputAttributes = [IO.File]::GetAttributes($OutputDirectory)
    if (($outputAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail 'OUTPUT_DIRECTORY must already be a nonsymlink directory'
    }
    $OutputDirectory = Get-FullPath $OutputDirectory
    if (Test-PathWithin $OutputDirectory $ProjectRoot) {
        Fail 'OUTPUT_DIRECTORY must be outside the source checkout'
    }

    $versionFile = [IO.Path]::Combine($ProjectRoot, 'VERSION')
    $infoFile = [IO.Path]::Combine($ProjectRoot, 'info.rkt')
    Assert-RegularNonsymlinkFile $versionFile 'VERSION'
    Assert-RegularNonsymlinkFile $infoFile 'info.rkt'
    $versionText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($versionFile))
    switch -CaseSensitive ($versionText) {
        "0.2.0-dev`n" { $productVersion = '0.2.0-dev'; $expectedPackageVersion = '0.1.900' }
        "0.2.0-rc.1`n" { $productVersion = '0.2.0-rc.1'; $expectedPackageVersion = '0.1.901' }
        "0.2.0`n" { $productVersion = '0.2.0'; $expectedPackageVersion = '0.2' }
        "0.3.0-dev`n" { $productVersion = '0.3.0-dev'; $expectedPackageVersion = '0.2.900' }
        "0.3.0`n" { $productVersion = '0.3.0'; $expectedPackageVersion = '0.3' }
        "0.4.0`n" { $productVersion = '0.4.0'; $expectedPackageVersion = '0.4' }
        default { Fail 'VERSION is outside the approved milestone states or lacks one terminal LF' }
    }
    $infoText = [IO.File]::ReadAllText($infoFile)
    $projection = [regex]::Escape("(define version `"$expectedPackageVersion`")")
    if ([regex]::Matches($infoText, "(?m)^$projection`r?$", [Text.RegularExpressions.RegexOptions]::CultureInvariant).Count -ne 1) {
        Fail 'info.rkt does not contain the approved VERSION projection'
    }

    $artifactRootName = "attalambda-$productVersion-$TargetIdentifier"
    $archiveName = "$artifactRootName.zip"
    $ArchivePath = [IO.Path]::Combine($OutputDirectory, $archiveName)
    $ChecksumPath = [IO.Path]::Combine($OutputDirectory, 'SHA256SUMS')
    if ([IO.File]::Exists($ArchivePath) -or [IO.Directory]::Exists($ArchivePath)) {
        Fail "refusing to replace existing output: $ArchivePath"
    }
    if ([IO.File]::Exists($ChecksumPath) -or [IO.Directory]::Exists($ChecksumPath)) {
        Fail "refusing to replace existing output: $ChecksumPath"
    }

    $racket = Get-Command racket.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $raco = Get-Command raco.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $racket -or $null -eq $raco) {
        Fail 'build requires racket.exe and raco.exe on PATH'
    }
    $racketBanner = (& $racket.Source --version | Out-String).TrimEnd("`r", "`n")
    if ($LASTEXITCODE -ne 0 -or $racketBanner -cne $RequiredRacketBanner) {
        Fail "build requires exactly $RequiredRacketBanner"
    }
    $racketVm = (& $racket.Source -e '(display (system-type (quote vm)))' | Out-String).TrimEnd("`r", "`n")
    if ($LASTEXITCODE -ne 0 -or $racketVm -cne 'chez-scheme') {
        Fail 'build requires the Racket CS virtual machine'
    }

    $tempParent = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { [IO.Path]::GetTempPath() } else { $env:RUNNER_TEMP }
    if (-not [IO.Directory]::Exists($tempParent)) {
        Fail 'temporary directory parent is unavailable'
    }
    $tempAttributes = [IO.File]::GetAttributes($tempParent)
    if (($tempAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail 'temporary directory parent is symlinked'
    }
    $tempParent = Get-FullPath $tempParent
    if (Test-PathWithin $tempParent $ProjectRoot) {
        Fail 'temporary directory parent must be outside the source checkout'
    }
    $BuildTempRoot = [IO.Path]::Combine($tempParent, "attalambda-windows-build-$([Guid]::NewGuid().ToString('N'))")
    [IO.Directory]::CreateDirectory($BuildTempRoot) | Out-Null

    $StagedArchive = [IO.Path]::Combine($OutputDirectory, ".$archiveName.building.$([Guid]::NewGuid().ToString('N'))")
    $StagedChecksum = [IO.Path]::Combine($OutputDirectory, ".SHA256SUMS.building.$([Guid]::NewGuid().ToString('N'))")
    $isolatedUserHome = [IO.Path]::Combine($BuildTempRoot, 'racket-user')
    $isolatedTemp = [IO.Path]::Combine($BuildTempRoot, 'tmp')
    $packageSource = [IO.Path]::Combine($BuildTempRoot, 'package-source')
    $compiledDirectory = [IO.Path]::Combine($BuildTempRoot, 'compiled-executable')
    $compiledExecutable = [IO.Path]::Combine($compiledDirectory, 'attalambda.exe')
    $rawDistribution = [IO.Path]::Combine($BuildTempRoot, 'raco-distribution')
    $artifactParent = [IO.Path]::Combine($BuildTempRoot, 'artifact')
    $artifactRoot = [IO.Path]::Combine($artifactParent, $artifactRootName)
    foreach ($directory in @($isolatedUserHome, $isolatedTemp, $packageSource, $compiledDirectory, $artifactParent)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    foreach ($name in @('PLTCOLLECTS', 'PLTADDONDIR', 'PLTCONFIGDIR', 'PLTUSERHOME', 'TEMP', 'TMP', 'TMPDIR', 'SOURCE_DATE_EPOCH')) {
        $SavedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    foreach ($name in @('PLTCOLLECTS', 'PLTADDONDIR', 'PLTCONFIGDIR')) {
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }
    [Environment]::SetEnvironmentVariable('PLTUSERHOME', $isolatedUserHome, 'Process')
    [Environment]::SetEnvironmentVariable('TEMP', $isolatedTemp, 'Process')
    [Environment]::SetEnvironmentVariable('TMP', $isolatedTemp, 'Process')
    [Environment]::SetEnvironmentVariable('TMPDIR', $isolatedTemp, 'Process')
    [Environment]::SetEnvironmentVariable('SOURCE_DATE_EPOCH', '0', 'Process')
    $EnvironmentChanged = $true

    Invoke-NativeChecked $racket.Source @('-e', '(require lazy)') 'bundled lazy-package verification'
    $fullDistribution = (& $raco.Source pkg show --all --rx '^main-distribution$' | Out-String)
    if ($LASTEXITCODE -ne 0 -or $fullDistribution -notmatch '(?m)^\s*main-distribution(?:[*\s]|$)') {
        Fail 'build requires the full Racket distribution'
    }

    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $git) {
        Fail 'build requires git.exe on PATH'
    }
    $sourceCommit = (& $git.Source -C $ProjectRoot rev-parse --verify HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') {
        Fail 'could not determine the source commit'
    }
    $gitSafePathspec = @(
        '.',
        ':(exclude,icase,glob).env', ':(exclude,icase,glob)*.env',
        ':(exclude,icase,glob).env.*', ':(exclude,icase,glob)*.env.*',
        ':(exclude,icase,glob)**/.env', ':(exclude,icase,glob)**/*.env',
        ':(exclude,icase,glob)**/.env.*', ':(exclude,icase,glob)**/*.env.*'
    )
    & $git.Source -C $ProjectRoot diff --quiet -- @gitSafePathspec
    $worktreeStatus = $LASTEXITCODE
    if ($worktreeStatus -notin @(0, 1)) {
        Fail 'git worktree inspection failed'
    }
    & $git.Source -C $ProjectRoot diff --cached --quiet -- @gitSafePathspec
    $indexStatus = $LASTEXITCODE
    if ($indexStatus -notin @(0, 1)) {
        Fail 'git index inspection failed'
    }
    $untrackedSources = @(& $git.Source -C $ProjectRoot ls-files --others --exclude-standard -- @gitSafePathspec | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($LASTEXITCODE -ne 0) {
        Fail 'git untracked-source inspection failed'
    }
    $sourceTreeDirty = ($worktreeStatus -eq 1 -or $indexStatus -eq 1 -or $untrackedSources.Count -gt 0)
    if ($sourceTreeDirty -and -not $AllowDirty) {
        Fail 'source tree has uncommitted changes; commit them or use -AllowDirty for internal testing'
    }
    $sourceTreeState = if ($sourceTreeDirty) { 'uncommitted changes allowed for internal development testing' } else { 'clean' }

    Copy-RegularFile $infoFile ([IO.Path]::Combine($packageSource, 'info.rkt')) 'info.rkt'
    Copy-RegularFile $versionFile ([IO.Path]::Combine($packageSource, 'VERSION')) 'VERSION'
    foreach ($sourceDirectoryName in @('core', 'effects', 'lang', 'macros', 'runner', 'runtime')) {
        $sourceDirectory = [IO.Path]::Combine($ProjectRoot, $sourceDirectoryName)
        if (-not [IO.Directory]::Exists($sourceDirectory)) {
            Fail "package source directory is unavailable: $sourceDirectoryName"
        }
        $sourceAttributes = [IO.File]::GetAttributes($sourceDirectory)
        if (($sourceAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Fail "package source directory is symlinked: $sourceDirectoryName"
        }
        foreach ($entry in @(Get-SafeTreeEntries -Root $sourceDirectory -SkipCompiled)) {
            if ($entry.IsDirectory) {
                continue
            }
            if (-not $entry.RelativePath.EndsWith('.rkt', [StringComparison]::Ordinal)) {
                Fail "unexpected non-Racket package source: $sourceDirectoryName/$($entry.RelativePath)"
            }
            $relativePath = "$sourceDirectoryName/$($entry.RelativePath)"
            Copy-RegularFile $entry.FullPath ([IO.Path]::Combine($packageSource, $relativePath.Replace('/', '\'))) $relativePath
        }
    }

    Invoke-NativeChecked $raco.Source @('pkg', 'install', '--batch', '--scope', 'user', '--copy', '--name', 'attalambda', '--deps', 'fail', '--no-docs', '--fail-fast', $packageSource) 'isolated package installation'
    Invoke-NativeChecked $raco.Source @('exe', '--embed-dlls', '-o', $compiledExecutable, '++lang', 'attalambda', [IO.Path]::Combine($packageSource, 'runner', 'attalambda.rkt')) 'native executable build'

    $compiledVersion = (& $compiledExecutable --version | Out-String).TrimEnd("`r", "`n")
    if ($LASTEXITCODE -ne 0 -or $compiledVersion -cne "AttaLambda $productVersion") {
        Fail 'compiled runner version does not match VERSION'
    }

    Invoke-NativeChecked $raco.Source @('distribute', $rawDistribution, $compiledExecutable) 'native distribution build'
    $rawEntries = @(Get-SafeTreeEntries -Root $rawDistribution -RejectDotenv)
    $rawFiles = @($rawEntries | Where-Object { -not $_.IsDirectory })
    $rawExecutables = @($rawFiles | Where-Object { [IO.Path]::GetFileName($_.FullPath) -ceq 'attalambda.exe' })
    if ($rawExecutables.Count -ne 1 -or $rawFiles.Count -ne 1) {
        $observed = ($rawFiles.RelativePath -join ', ')
        Fail "raco distribute produced unexpected support files instead of one embedded attalambda.exe: $observed"
    }

    $artifactBin = [IO.Path]::Combine($artifactRoot, 'bin')
    $artifactLib = [IO.Path]::Combine($artifactRoot, 'lib')
    $artifactExamples = [IO.Path]::Combine($artifactRoot, 'examples')
    [IO.Directory]::CreateDirectory($artifactBin) | Out-Null
    [IO.Directory]::CreateDirectory($artifactLib) | Out-Null
    [IO.Directory]::CreateDirectory($artifactExamples) | Out-Null
    [IO.File]::Move($rawExecutables[0].FullPath, [IO.Path]::Combine($artifactBin, 'attalambda.exe'))

    foreach ($exampleName in @('hello.attl', 'stdout.attl', 'file-round-trip.attl', 'http-server.attl', 'foundations.attl')) {
        Copy-RegularFile ([IO.Path]::Combine($ProjectRoot, 'examples', $exampleName)) ([IO.Path]::Combine($artifactExamples, $exampleName)) "canonical example $exampleName"
    }
    foreach ($assetName in @('GETTING_STARTED.md.in', 'THIRD_PARTY_NOTICES.md.in')) {
        Assert-RegularNonsymlinkFile ([IO.Path]::Combine($ProjectRoot, 'distribution', $assetName)) "distribution asset $assetName"
    }
    $licensePath = [IO.Path]::Combine($ProjectRoot, 'LICENSE')
    Assert-RegularNonsymlinkFile $licensePath 'repository LICENSE'

    $guide = [IO.File]::ReadAllText([IO.Path]::Combine($ProjectRoot, 'distribution', 'GETTING_STARTED.md.in'))
    $verifyCommand = '$line = @(Get-Content .\SHA256SUMS | Where-Object { $_ -like "*' + $archiveName + '" }); if ($line.Count -ne 1) { throw ''checksum entry mismatch'' }; $expected = ($line[0] -split ''\s+'')[0]; $actual = (Get-FileHash .\' + $archiveName + ' -Algorithm SHA256).Hash.ToLowerInvariant(); if ($actual -cne $expected) { throw ''SHA-256 mismatch'' }'
    $guide = $guide.Replace('@VERSION@', $productVersion)
    $guide = $guide.Replace('@TARGET_NAME@', 'Windows x86-64')
    $guide = $guide.Replace('@ARCHIVE_NAME@', $archiveName)
    $guide = $guide.Replace('@COMMAND_LANGUAGE@', 'powershell')
    $guide = $guide.Replace('@VERIFY_COMMAND@', $verifyCommand)
    $guide = $guide.Replace('@EXTRACT_COMMAND@', "Expand-Archive -LiteralPath .\$archiveName -DestinationPath .")
    $guide = $guide.Replace('@ENTER_COMMAND@', "Set-Location .\$artifactRootName")
    $guide = $guide.Replace('@EXECUTABLE@', '.\bin\attalambda.exe')
    $guide = $guide.Replace('@PATH_SEPARATOR@', '\')
    $guide = $guide.Replace('@DEPENDENCY_KIND@', 'Windows system-DLL assumptions')
    if ($guide -match '@[A-Z_]+@') {
        Fail 'unexpanded getting-started placeholder'
    }
    Write-LfUtf8 ([IO.Path]::Combine($artifactRoot, 'GETTING_STARTED.md')) $guide
    Copy-RegularFile $licensePath ([IO.Path]::Combine($artifactRoot, 'LICENSE')) 'repository LICENSE'
    $licenseDigest = Get-Sha256 $licensePath
    $noticePath = [IO.Path]::Combine($ProjectRoot, 'distribution', 'THIRD_PARTY_NOTICES.md.in')
    if ((Get-Sha256 $noticePath) -cne $ApprovedNoticeSha256) {
        Fail 'third-party notices differ from the exact Phase 29 approval'
    }
    Copy-RegularFile $noticePath ([IO.Path]::Combine($artifactRoot, 'THIRD_PARTY_NOTICES.md')) 'approved third-party notices'

    $attalambdaExecutable = [IO.Path]::Combine($artifactBin, 'attalambda.exe')
    $distributedVersion = (& $attalambdaExecutable --version | Out-String).TrimEnd("`r", "`n")
    if ($LASTEXITCODE -ne 0 -or $distributedVersion -cne "AttaLambda $productVersion") {
        Fail 'distributed runner version does not match VERSION after canonical relocation'
    }

    $dumpbin = Find-Dumpbin
    $artifactEntries = @(Get-SafeTreeEntries -Root $artifactRoot -RejectDotenv)
    $runtimeFiles = @($artifactEntries | Where-Object { -not $_.IsDirectory -and ($_.RelativePath.StartsWith('bin/', [StringComparison]::Ordinal) -or $_.RelativePath.StartsWith('lib/', [StringComparison]::Ordinal)) })
    $peFiles = @($runtimeFiles | Where-Object { $_.RelativePath -match '(?i)[.](exe|dll)$' })
    if ($peFiles.Count -eq 0 -or $peFiles.Count -ne $runtimeFiles.Count) {
        Fail 'runtime tree contains no PE file or an unclassified non-PE file'
    }
    $runtimeByBaseName = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($runtimeFile in $runtimeFiles) {
        $baseName = [IO.Path]::GetFileName($runtimeFile.FullPath)
        if ($runtimeByBaseName.ContainsKey($baseName)) {
            Fail "runtime tree contains a duplicate dependency basename: $baseName"
        }
        $runtimeByBaseName.Add($baseName, $runtimeFile.RelativePath)
    }
    $peInventory = [Collections.Generic.List[string]]::new()
    $bundledDependencies = [Collections.Generic.List[string]]::new()
    $systemDependencies = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $system32 = [Environment]::GetFolderPath('System')
    foreach ($peFile in $peFiles) {
        $machine = Get-PeMachine $peFile.FullPath
        if ($machine -ne 0x8664) {
            Fail "PE file has unexpected machine type: $($peFile.RelativePath) (0x$($machine.ToString('x4')))"
        }
        $peInventory.Add("$($peFile.RelativePath): PE32+ machine 0x8664")
        foreach ($dependency in @(Get-PeDependencies $dumpbin $peFile.FullPath)) {
            if ($runtimeByBaseName.ContainsKey($dependency)) {
                $bundledDependencies.Add("$($peFile.RelativePath) -> $dependency -> $($runtimeByBaseName[$dependency])")
            }
            elseif ($dependency.StartsWith('api-ms-win-', [StringComparison]::OrdinalIgnoreCase) -or
                    $dependency.StartsWith('ext-ms-', [StringComparison]::OrdinalIgnoreCase) -or
                    [IO.File]::Exists([IO.Path]::Combine($system32, $dependency))) {
                [void] $systemDependencies.Add($dependency)
            }
            else {
                Fail "PE file has an unbundled non-system dependency: $($peFile.RelativePath) -> $dependency"
            }
        }
    }
    if ($systemDependencies.Count -eq 0) {
        Fail 'dynamic system-DLL inventory is empty'
    }
    $peInventory = @($peInventory | Sort-Object -CaseSensitive)
    $bundledDependencies = @($bundledDependencies | Sort-Object -CaseSensitive -Unique)
    $systemDependencies = @($systemDependencies | Sort-Object)

    $signature = Get-AuthenticodeSignature -LiteralPath $attalambdaExecutable
    $authenticodeStatus = [string] $signature.Status
    if ($authenticodeStatus -notin @('NotSigned', 'Valid')) {
        Fail "attalambda.exe has an unacceptable Authenticode status: $authenticodeStatus"
    }

    $manifestPath = [IO.Path]::Combine($artifactRoot, 'BUILD-MANIFEST.txt')
    [IO.File]::WriteAllBytes($manifestPath, [byte[]]::new(0))
    $artifactEntries = @(Get-SafeTreeEntries -Root $artifactRoot -RejectDotenv)
    $artifactInventory = @($artifactEntries | Where-Object { -not $_.IsDirectory } | ForEach-Object { $_.RelativePath } | Sort-Object -CaseSensitive)
    $manifest = [Text.StringBuilder]::new()
    [void] $manifest.Append("AttaLambda build manifest`n")
    [void] $manifest.Append("Manifest format: 1`n")
    [void] $manifest.Append("Product version: $productVersion`n")
    [void] $manifest.Append("Source commit: $sourceCommit`n")
    [void] $manifest.Append("Source tree state: $sourceTreeState`n")
    [void] $manifest.Append("Target identifier: $TargetIdentifier`n")
    [void] $manifest.Append("Racket version: $RequiredRacketVersion`n")
    [void] $manifest.Append("Racket variant: CS`n")
    [void] $manifest.Append("Artifact status: final release artifact`n")
    [void] $manifest.Append("Repository license SHA-256: $licenseDigest`n")
    [void] $manifest.Append("Third-party notices SHA-256: $ApprovedNoticeSha256`n")
    [void] $manifest.Append("Archive checksum: external sibling SHA256SUMS`n")
    [void] $manifest.Append("Executable Authenticode status: $authenticodeStatus`n")
    [void] $manifest.Append("`nArtifact file inventory:`n")
    foreach ($line in $artifactInventory) { [void] $manifest.Append("  $line`n") }
    [void] $manifest.Append("`nPE x86-64 inventory:`n")
    foreach ($line in $peInventory) { [void] $manifest.Append("  $line`n") }
    [void] $manifest.Append("`nBundled runtime dependency inventory:`n")
    if ($bundledDependencies.Count -eq 0) {
        [void] $manifest.Append("  (none; DLLs embedded by raco exe --embed-dlls)`n")
    }
    else {
        foreach ($line in $bundledDependencies) { [void] $manifest.Append("  $line`n") }
    }
    [void] $manifest.Append("`nObserved dynamic system-DLL assumptions:`n")
    foreach ($line in $systemDependencies) { [void] $manifest.Append("  $line`n") }
    Write-LfUtf8 $manifestPath $manifest.ToString()

    $artifactFiles = @((Get-SafeTreeEntries -Root $artifactRoot -RejectDotenv) | Where-Object { -not $_.IsDirectory } | ForEach-Object { $_.FullPath })
    $forbiddenBuildPaths = [Collections.Generic.List[string]]::new()
    foreach ($path in @($ProjectRoot, $BuildTempRoot, $isolatedUserHome, $packageSource, $rawDistribution)) {
        $forbiddenBuildPaths.Add($path)
    }
    $toolchainRoot = Get-FullPath ([IO.Path]::GetDirectoryName($racket.Source))
    $standardToolchainRoots = @(
        (Get-FullPath ([IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'Racket'))),
        (Get-FullPath ([IO.Path]::Combine([Environment]::GetFolderPath('ProgramFilesX86'), 'Racket')))
    )
    if (@($standardToolchainRoots | Where-Object { $_.Equals($toolchainRoot, [StringComparison]::OrdinalIgnoreCase) }).Count -ne 1) {
        $forbiddenBuildPaths.Add($toolchainRoot)
    }
    Assert-NoForbiddenBuildPaths $artifactFiles $forbiddenBuildPaths.ToArray()

    New-DeterministicZip $artifactParent $artifactRootName $StagedArchive
    $archiveDigest = Get-Sha256 $StagedArchive
    [IO.File]::WriteAllText($StagedChecksum, "$archiveDigest  $archiveName`n", [Text.ASCIIEncoding]::new())
    $archiveBytes = ([IO.FileInfo] $StagedArchive).Length
    $unpackedBytes = [int64] 0
    foreach ($artifactFile in $artifactFiles) {
        $unpackedBytes += ([IO.FileInfo] $artifactFile).Length
    }

    [IO.File]::Move($StagedArchive, $ArchivePath, $false)
    $StagedArchive = $null
    $ArchiveCreated = $true
    [IO.File]::Move($StagedChecksum, $ChecksumPath, $false)
    $StagedChecksum = $null
    $ChecksumCreated = $true
    $OutputsComplete = $true

    [Console]::Out.WriteLine("archive=$ArchivePath")
    [Console]::Out.WriteLine("checksum_manifest=$ChecksumPath")
    [Console]::Out.WriteLine("sha256=$archiveDigest")
    [Console]::Out.WriteLine("compressed_bytes=$archiveBytes")
    [Console]::Out.WriteLine("unpacked_regular_file_bytes=$unpackedBytes")
    [Console]::Out.WriteLine("artifact_files=$($artifactFiles.Count)")
    [Console]::Out.WriteLine("runtime_files=$($runtimeFiles.Count)")
    [Console]::Out.WriteLine("pe_files=$($peFiles.Count)")
    [Console]::Out.WriteLine("system_dlls=$($systemDependencies -join ',')")
    [Console]::Out.WriteLine("authenticode_status=$authenticodeStatus")
    $Succeeded = $true
}
catch {
    [Console]::Error.WriteLine("$ProgramName`: $($_.Exception.Message)")
}
finally {
    if ($EnvironmentChanged) {
        foreach ($name in $SavedEnvironment.Keys) {
            if ($null -eq $SavedEnvironment[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $SavedEnvironment[$name], 'Process')
            }
        }
    }
    if ($null -ne $BuildTempRoot -and [IO.Directory]::Exists($BuildTempRoot)) {
        $expectedPrefix = [IO.Path]::Combine((Get-FullPath ([IO.Path]::GetDirectoryName($BuildTempRoot))), 'attalambda-windows-build-')
        if ((Get-FullPath $BuildTempRoot).StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $BuildTempRoot -Recurse -Force
        }
    }
    foreach ($stagedPath in @($StagedArchive, $StagedChecksum)) {
        if ($null -ne $stagedPath -and [IO.File]::Exists($stagedPath)) {
            [IO.File]::Delete($stagedPath)
        }
    }
    if (-not $OutputsComplete) {
        if ($ArchiveCreated -and $null -ne $ArchivePath -and [IO.File]::Exists($ArchivePath)) {
            [IO.File]::Delete($ArchivePath)
        }
        if ($ChecksumCreated -and $null -ne $ChecksumPath -and [IO.File]::Exists($ChecksumPath)) {
            [IO.File]::Delete($ChecksumPath)
        }
    }
}

if (-not $Succeeded) {
    exit 2
}
