param(
    [Parameter(Position = 0)]
    [string] $OutputDirectory,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramName = 'test-windows-distribution'
$TargetIdentifier = 'windows-x86_64'
$Usage = @'
Usage:
  tooling/test-windows-distribution.ps1 OUTPUT_DIRECTORY

Test one transferred final Windows x86-64 release archive on
a clean Windows consumer with no Racket installation or source checkout,
including relocation to a different drive and a path containing spaces.
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

function Get-SafeTreeEntries {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
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

function Assert-ExactSequence([object[]] $Actual, [object[]] $Expected, [string] $Label) {
    if ($Actual.Count -ne $Expected.Count) {
        Fail "$Label differs from the contract"
    }
    for ($index = 0; $index -lt $Actual.Count; $index += 1) {
        if ([string] $Actual[$index] -cne [string] $Expected[$index]) {
            Fail "$Label differs from the contract"
        }
    }
}

function Get-ManifestSection([string] $Manifest, [string] $Heading) {
    $lines = $Manifest.Replace("`r`n", "`n").Replace("`r", "`n").Split("`n")
    $inside = $false
    $result = [Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -ceq "$Heading`:") {
            $inside = $true
            continue
        }
        if ($inside -and $line.StartsWith('  ', [StringComparison]::Ordinal)) {
            $result.Add($line.Substring(2))
            continue
        }
        if ($inside) {
            break
        }
    }
    if ($result.Count -eq 0) {
        Fail "build manifest section is absent or empty: $Heading"
    }
    return $result.ToArray()
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
    $vswhereResult = Invoke-CapturedProcess `
        -Executable $vswhere `
        -Arguments @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath') `
        -WorkingDirectory ([IO.Path]::GetDirectoryName($vswhere))
    $installationPaths = @(
        $vswhereResult.Stdout.Replace("`r`n", "`n").Replace("`r", "`n").Split("`n") |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($vswhereResult.Status -ne 0 -or $installationPaths.Count -ne 1) {
        Fail 'Visual Studio x64 build tools are unavailable'
    }
    $msvcRoot = [IO.Path]::Combine($installationPaths[0].Trim(), 'VC', 'Tools', 'MSVC')
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
    $result = Invoke-CapturedProcess `
        -Executable $Dumpbin `
        -Arguments @('/NOLOGO', '/DEPENDENTS', $Path) `
        -WorkingDirectory ([IO.Path]::GetDirectoryName($Path))
    if ($result.Status -ne 0) {
        Fail "dumpbin dependency inspection failed for $Path"
    }
    $dependencies = @(
        $result.Stdout.Replace("`r`n", "`n").Replace("`r", "`n").Split("`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '(?i)^[a-z0-9_.-]+[.]dll$' } |
            Sort-Object -Unique
    )
    if ($dependencies.Count -eq 0) {
        Fail "PE dependency inventory is empty for $Path"
    }
    return $dependencies
}

function Assert-NoBuildRunnerPaths([string[]] $Files) {
    # The builder rejects the complete checkout, build-root, package-source,
    # and isolated-user-home paths while those paths are known. An observed
    # Windows executable retained only the isolated user home's directory
    # basename; the cross-drive no-Racket run below proves that basename is not
    # an operational dependency.
    $forbiddenFragments = [ordered]@{
        'github-checkout-segment' = '\a\attalambda\attalambda\'
        'runner-temp-segment' = '\_temp\'
        'runner-profile-segment' = '\runneradmin\'
        'build-root-name' = 'attalambda-windows-build-'
        'package-source-segment' = '\package-source\'
    }
    foreach ($file in $Files) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $latin = [Text.Encoding]::Latin1.GetString($bytes)
        $utf16 = [Text.Encoding]::Unicode.GetString($bytes)
        foreach ($entry in $forbiddenFragments.GetEnumerator()) {
            $fragment = $entry.Value
            if ($latin.Contains($fragment, [StringComparison]::OrdinalIgnoreCase) -or
                $utf16.Contains($fragment, [StringComparison]::OrdinalIgnoreCase)) {
                Fail "artifact matched forbidden path marker $($entry.Key) in $([IO.Path]::GetFileName($file))"
            }
        }
    }
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string] $Executable,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [hashtable] $Environment = @{},
        [int] $TimeoutMilliseconds = 20000
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }
    foreach ($name in @('PLTCOLLECTS', 'PLTADDONDIR', 'PLTCONFIGDIR', 'PLTUSERHOME')) {
        [void] $startInfo.Environment.Remove($name)
    }
    foreach ($name in $Environment.Keys) {
        $startInfo.Environment[$name] = [string] $Environment[$name]
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) {
            Fail "could not start process: $Executable"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill($true)
            $process.WaitForExit()
            Fail "process timed out: $Executable"
        }
        $process.WaitForExit()
        $clock.Stop()
        return [PSCustomObject]@{
            Status = $process.ExitCode
            Stdout = $stdoutTask.GetAwaiter().GetResult()
            Stderr = $stderrTask.GetAwaiter().GetResult()
            Milliseconds = $clock.ElapsedMilliseconds
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-ProcessResult($Result, [int] $Status, [string] $Stdout, [string] $Stderr, [string] $Label) {
    if ($Result.Status -ne $Status) {
        Fail "$Label exited with $($Result.Status) instead of $Status"
    }
    if ($Result.Stdout -cne $Stdout) {
        Fail "$Label stdout differs from the contract"
    }
    if ($Result.Stderr -cne $Stderr) {
        Fail "$Label stderr differs from the contract"
    }
}

function Copy-SafeTree([string] $Source, [string] $Destination) {
    if ([IO.Directory]::Exists($Destination) -or [IO.File]::Exists($Destination)) {
        Fail "relocation destination already exists: $Destination"
    }
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $entries = @(Get-SafeTreeEntries -Root $Source -RejectDotenv)
    foreach ($entry in @($entries | Where-Object { $_.IsDirectory } | Sort-Object { $_.RelativePath.Length })) {
        [IO.Directory]::CreateDirectory([IO.Path]::Combine($Destination, $entry.RelativePath.Replace('/', '\'))) | Out-Null
    }
    foreach ($entry in @($entries | Where-Object { -not $_.IsDirectory })) {
        $target = [IO.Path]::Combine($Destination, $entry.RelativePath.Replace('/', '\'))
        [IO.File]::Copy($entry.FullPath, $target, $false)
    }
}

function Invoke-HttpAcceptance([string] $Executable, [string] $Source, [string] $WorkingDirectory) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    [void] $startInfo.ArgumentList.Add($Source)
    foreach ($name in @('PLTCOLLECTS', 'PLTADDONDIR', 'PLTCONFIGDIR', 'PLTUSERHOME')) {
        [void] $startInfo.Environment.Remove($name)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            Fail 'could not start packaged HTTP example'
        }
        $announcementTask = $process.StandardOutput.ReadLineAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $announcementTask.Wait(20000)) {
            $process.Kill($true)
            Fail 'packaged HTTP example did not announce a loopback URL'
        }
        $announcement = $announcementTask.GetAwaiter().GetResult()
        if ($announcement -notmatch '^Listening on http://127[.]0[.]0[.]1:([0-9]+)/lambda$') {
            $process.Kill($true)
            Fail 'packaged HTTP example announced an unexpected URL'
        }
        $port = [int] $Matches[1]
        if ($port -lt 1 -or $port -gt 65535) {
            $process.Kill($true)
            Fail 'packaged HTTP example announced an invalid port'
        }
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $client.ReceiveTimeout = 20000
            $client.SendTimeout = 20000
            $client.Connect('127.0.0.1', $port)
            $network = $client.GetStream()
            try {
                $request = [Text.Encoding]::ASCII.GetBytes("GET /lambda HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n`r`n")
                $network.Write($request, 0, $request.Length)
                $response = [IO.MemoryStream]::new()
                try {
                    $buffer = [byte[]]::new(4096)
                    while (($count = $network.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $response.Write($buffer, 0, $count)
                    }
                    $responseText = [Text.Encoding]::UTF8.GetString($response.ToArray())
                }
                finally {
                    $response.Dispose()
                }
            }
            finally {
                $network.Dispose()
            }
        }
        finally {
            $client.Dispose()
        }
        if (-not $process.WaitForExit(20000)) {
            $process.Kill($true)
            Fail 'packaged HTTP example did not stop after one request'
        }
        $process.WaitForExit()
        $remainingStdout = $process.StandardOutput.ReadToEnd()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            Fail "packaged HTTP example exited with status $($process.ExitCode)"
        }
        if ($remainingStdout -cne '' -or $stderr -cne '') {
            Fail 'packaged HTTP example wrote unexpected output'
        }
        $separator = $responseText.IndexOf("`r`n`r`n", [StringComparison]::Ordinal)
        if ($separator -lt 0 -or -not $responseText.StartsWith("HTTP/1.1 200 OK`r`n", [StringComparison]::Ordinal)) {
            Fail 'packaged HTTP response status or framing differs from the contract'
        }
        $body = $responseText.Substring($separator + 4)
        if ($body -cne "Hello from AttaLambda.`n") {
            Fail 'packaged HTTP response body differs from the contract'
        }
    }
    finally {
        if (-not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
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

$ScratchRoot = $null
$RelocatedParent = $null
$Succeeded = $false

try {
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess -or
        [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
        Fail 'consumer requires native Windows x86-64'
    }
    if (-not [IO.Directory]::Exists($OutputDirectory)) {
        Fail 'OUTPUT_DIRECTORY must be a nonsymlink directory'
    }
    $outputAttributes = [IO.File]::GetAttributes($OutputDirectory)
    if (($outputAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail 'OUTPUT_DIRECTORY must be a nonsymlink directory'
    }
    $OutputDirectory = Get-FullPath $OutputDirectory

    if ($null -ne (Get-Command racket.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        Fail 'consumer unexpectedly has a racket command'
    }
    if ($null -ne (Get-Command raco.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        Fail 'consumer unexpectedly has a raco command'
    }
    $currentDirectory = Get-FullPath (Get-Location).Path
    foreach ($checkoutMarker in @('.git', 'info.rkt', 'core', 'runner')) {
        $markerPath = [IO.Path]::Combine($currentDirectory, $checkoutMarker)
        if ([IO.File]::Exists($markerPath) -or [IO.Directory]::Exists($markerPath)) {
            Fail 'consumer unexpectedly has a source checkout'
        }
    }

    $transferEntries = [Collections.Generic.List[string]]::new()
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($OutputDirectory)) {
        $name = [IO.Path]::GetFileName($path)
        if (Test-DotenvName $name) {
            Fail 'transfer directory contains a forbidden dotenv path'
        }
        $attributes = [IO.File]::GetAttributes($path)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Fail 'transfer directory contains a reparse point'
        }
        $transferEntries.Add($path)
    }
    $archives = @($transferEntries | Where-Object { [IO.File]::Exists($_) -and [IO.Path]::GetFileName($_) -match '^attalambda-.+-windows-x86_64[.]zip$' })
    if ($archives.Count -ne 1) {
        Fail 'OUTPUT_DIRECTORY must contain exactly one windows-x86_64 archive'
    }
    $archivePath = $archives[0]
    $archiveName = [IO.Path]::GetFileName($archivePath)
    $checksumPath = [IO.Path]::Combine($OutputDirectory, 'SHA256SUMS')
    Assert-RegularNonsymlinkFile $archivePath 'transferred archive'
    Assert-RegularNonsymlinkFile $checksumPath 'transferred SHA256SUMS'

    $nameMatch = [regex]::Match($archiveName, '^attalambda-(0[.]2[.]0(?:-dev|-rc[.]1)?|0[.]3[.]0(?:-dev)?|0[.]4[.]0)-windows-x86_64[.]zip$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $nameMatch.Success) {
        Fail 'archive filename contains an unapproved product version or target'
    }
    $productVersion = $nameMatch.Groups[1].Value
    $artifactRootName = [IO.Path]::GetFileNameWithoutExtension($archiveName)

    $checksumBytes = [IO.File]::ReadAllBytes($checksumPath)
    if ($checksumBytes.Count -eq 0 -or $checksumBytes[-1] -ne 10 -or $checksumBytes -contains 13 -or
        @($checksumBytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
        Fail 'SHA256SUMS must be ASCII with exactly one terminal LF'
    }
    $checksumText = [Text.Encoding]::ASCII.GetString($checksumBytes)
    $checksumPattern = "^[0-9a-f]{64}  $([regex]::Escape($archiveName))`n$"
    if ($checksumText -notmatch $checksumPattern) {
        Fail 'SHA256SUMS must contain exactly the versioned Windows archive'
    }
    $expectedDigest = $checksumText.Substring(0, 64)
    if ((Get-Sha256 $archivePath) -cne $expectedDigest) {
        Fail 'transferred archive checksum mismatch'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $seenNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $entryName = $entry.FullName
            if ([string]::IsNullOrEmpty($entryName) -or $entryName.Contains('\') -or
                $entryName.StartsWith('/', [StringComparison]::Ordinal) -or
                $entryName -match '^[a-zA-Z]:' -or
                -not $seenNames.Add($entryName)) {
                Fail 'archive contains an unsafe or case-duplicate path'
            }
            $parts = @($entryName.TrimEnd('/').Split('/') | Where-Object { $_ -ne '' })
            if ($parts.Count -eq 0 -or $parts[0] -cne $artifactRootName -or
                @($parts | Where-Object { $_ -eq '..' -or (Test-DotenvName $_) }).Count -ne 0) {
                Fail 'archive contains an entry outside its one safe root directory'
            }
            $unixType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000) {
                Fail 'archive contains a symbolic-link entry'
            }
            if ($entry.LastWriteTime.UtcDateTime -ne [DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)) {
                Fail 'archive entry timestamp is not deterministic'
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    $scratchParent = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { [IO.Path]::GetTempPath() } else { $env:RUNNER_TEMP }
    $scratchParent = Get-FullPath $scratchParent
    $ScratchRoot = [IO.Path]::Combine($scratchParent, "attalambda-windows-consumer-$([Guid]::NewGuid().ToString('N'))")
    $firstParent = [IO.Path]::Combine($ScratchRoot, 'first extraction path with spaces')
    $firstRoot = [IO.Path]::Combine($firstParent, $artifactRootName)
    [IO.Directory]::CreateDirectory($firstParent) | Out-Null
    [IO.File]::Copy($archivePath, [IO.Path]::Combine($firstParent, $archiveName), $false)
    [IO.File]::Copy($checksumPath, [IO.Path]::Combine($firstParent, 'SHA256SUMS'), $false)
    Push-Location -LiteralPath $firstParent
    try {
        $line = @(Get-Content .\SHA256SUMS | Where-Object { $_ -like "*$archiveName" })
        if ($line.Count -ne 1) { throw 'checksum entry mismatch' }
        $expected = ($line[0] -split '\s+')[0]
        $actual = (Get-FileHash .\$archiveName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $expected) { throw 'SHA-256 mismatch' }
        Expand-Archive -LiteralPath .\$archiveName -DestinationPath .
        Set-Location .\$artifactRootName
    }
    finally {
        Pop-Location
    }
    if (-not [IO.Directory]::Exists($firstRoot)) {
        Fail 'archive root is unavailable after extraction'
    }
    $artifactEntries = @(Get-SafeTreeEntries -Root $firstRoot -RejectDotenv)

    $requiredFiles = @(
        'bin/attalambda.exe',
        'examples/hello.attl', 'examples/stdout.attl',
        'examples/file-round-trip.attl', 'examples/http-server.attl',
        'examples/foundations.attl',
        'GETTING_STARTED.md', 'BUILD-MANIFEST.txt',
        'LICENSE', 'THIRD_PARTY_NOTICES.md'
    )
    foreach ($relativePath in $requiredFiles) {
        Assert-RegularNonsymlinkFile ([IO.Path]::Combine($firstRoot, $relativePath.Replace('/', '\'))) "required artifact file $relativePath"
    }
    $libPath = [IO.Path]::Combine($firstRoot, 'lib')
    if (-not [IO.Directory]::Exists($libPath)) {
        Fail 'artifact is missing lib/'
    }
    if (@(Get-SafeTreeEntries -Root $libPath -RejectDotenv).Count -ne 0) {
        Fail 'embedded-DLL Windows artifact unexpectedly has loose lib/ contents'
    }
    if ([IO.File]::Exists([IO.Path]::Combine($firstRoot, 'UNPUBLISHED-DEVELOPMENT-ARTIFACT.txt')) -or
        [IO.Directory]::Exists([IO.Path]::Combine($firstRoot, 'UNPUBLISHED-DEVELOPMENT-ARTIFACT.txt'))) {
        Fail 'release archive contains the retired development warning'
    }

    $topLevel = @($artifactEntries | Where-Object { -not $_.RelativePath.Contains('/') } | ForEach-Object { $_.RelativePath } | Sort-Object -CaseSensitive)
    $expectedTopLevel = @('BUILD-MANIFEST.txt', 'GETTING_STARTED.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'bin', 'examples', 'lib') | Sort-Object -CaseSensitive
    Assert-ExactSequence $topLevel $expectedTopLevel 'artifact top-level layout'
    $binInventory = @($artifactEntries | Where-Object { $_.RelativePath.StartsWith('bin/', [StringComparison]::Ordinal) -and -not $_.IsDirectory } | ForEach-Object { $_.RelativePath.Substring(4) } | Sort-Object -CaseSensitive)
    Assert-ExactSequence $binInventory @('attalambda.exe') 'artifact bin/ inventory'
    $exampleInventory = @($artifactEntries | Where-Object { $_.RelativePath.StartsWith('examples/', [StringComparison]::Ordinal) -and -not $_.IsDirectory } | ForEach-Object { $_.RelativePath.Substring(9) } | Sort-Object -CaseSensitive)
    Assert-ExactSequence $exampleInventory (@('file-round-trip.attl', 'foundations.attl', 'hello.attl', 'http-server.attl', 'stdout.attl') | Sort-Object -CaseSensitive) 'artifact examples/ inventory'

    $manifestPath = [IO.Path]::Combine($firstRoot, 'BUILD-MANIFEST.txt')
    $manifest = [IO.File]::ReadAllText($manifestPath)
    foreach ($requiredLine in @(
        "Product version: $productVersion",
        "Target identifier: $TargetIdentifier",
        'Racket version: 9.3', 'Racket variant: CS',
        'Artifact status: final release artifact',
        'Repository license SHA-256: cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
        'Third-party notices SHA-256: 516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad',
        'Archive checksum: external sibling SHA256SUMS'
    )) {
        if (@($manifest.Replace("`r`n", "`n").Split("`n") | Where-Object { $_ -ceq $requiredLine }).Count -ne 1) {
            Fail "build manifest line is absent or duplicated: $requiredLine"
        }
    }
    if ($manifest -notmatch '(?m)^Source commit: [0-9a-f]{40}\r?$') {
        Fail 'build manifest source commit is invalid'
    }
    if ($manifest -match '(?im)(?:^|\s)[a-z]:\\|\\\\') {
        Fail 'build manifest contains an absolute Windows path'
    }
    $actualInventory = @($artifactEntries | Where-Object { -not $_.IsDirectory } | ForEach-Object { $_.RelativePath } | Sort-Object -CaseSensitive)
    $manifestInventory = @(Get-ManifestSection $manifest 'Artifact file inventory')
    Assert-ExactSequence $actualInventory $manifestInventory 'BUILD-MANIFEST.txt file inventory'
    if ((Get-Sha256 ([IO.Path]::Combine($firstRoot, 'LICENSE'))) -cne 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30') {
        Fail 'repository license bytes differ from the approved license'
    }
    if ((Get-Sha256 ([IO.Path]::Combine($firstRoot, 'THIRD_PARTY_NOTICES.md'))) -cne '516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad') {
        Fail 'third-party notices differ from the exact Phase 29 approval'
    }
    $guide = [IO.File]::ReadAllText([IO.Path]::Combine($firstRoot, 'GETTING_STARTED.md'))
    foreach ($guideCommand in @(
        "Get-FileHash .\$archiveName -Algorithm SHA256",
        "Expand-Archive -LiteralPath .\$archiveName -DestinationPath .",
        "Set-Location .\$artifactRootName",
        '.\bin\attalambda.exe --version',
        '.\bin\attalambda.exe examples\hello.attl',
        '.\bin\attalambda.exe my-program.attl'
    )) {
        if (-not $guide.Contains($guideCommand, [StringComparison]::Ordinal)) {
            Fail "guide command is absent: $guideCommand"
        }
    }

    $dumpbin = Find-Dumpbin
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
    $actualPe = [Collections.Generic.List[string]]::new()
    $actualBundled = [Collections.Generic.List[string]]::new()
    $actualSystem = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $system32 = [Environment]::GetFolderPath('System')
    foreach ($peFile in $peFiles) {
        $machine = Get-PeMachine $peFile.FullPath
        if ($machine -ne 0x8664) {
            Fail "PE file has unexpected machine type: $($peFile.RelativePath)"
        }
        $actualPe.Add("$($peFile.RelativePath): PE32+ machine 0x8664")
        foreach ($dependency in @(Get-PeDependencies $dumpbin $peFile.FullPath)) {
            if ($runtimeByBaseName.ContainsKey($dependency)) {
                $actualBundled.Add("$($peFile.RelativePath) -> $dependency -> $($runtimeByBaseName[$dependency])")
            }
            elseif ($dependency.StartsWith('api-ms-win-', [StringComparison]::OrdinalIgnoreCase) -or
                    $dependency.StartsWith('ext-ms-', [StringComparison]::OrdinalIgnoreCase) -or
                    [IO.File]::Exists([IO.Path]::Combine($system32, $dependency))) {
                [void] $actualSystem.Add($dependency)
            }
            else {
                Fail "PE file has an unbundled non-system dependency: $($peFile.RelativePath) -> $dependency"
            }
        }
    }
    $actualPe = @($actualPe | Sort-Object -CaseSensitive)
    $actualBundled = @($actualBundled | Sort-Object -CaseSensitive -Unique)
    $actualSystem = @($actualSystem | Sort-Object)
    $expectedPe = @(Get-ManifestSection $manifest 'PE x86-64 inventory')
    $expectedBundled = @(Get-ManifestSection $manifest 'Bundled runtime dependency inventory')
    if ($actualBundled.Count -eq 0) {
        $actualBundled = @('(none; DLLs embedded by raco exe --embed-dlls)')
    }
    $expectedSystem = @(Get-ManifestSection $manifest 'Observed dynamic system-DLL assumptions')
    Assert-ExactSequence $actualPe $expectedPe 'PE x86-64 inventory'
    Assert-ExactSequence $actualBundled $expectedBundled 'bundled runtime dependency inventory'
    Assert-ExactSequence $actualSystem $expectedSystem 'dynamic system-DLL inventory'

    $attalambda = [IO.Path]::Combine($firstRoot, 'bin', 'attalambda.exe')
    $signature = Get-AuthenticodeSignature -LiteralPath $attalambda
    $authenticodeStatus = [string] $signature.Status
    if ($authenticodeStatus -notin @('NotSigned', 'Valid') -or
        -not $manifest.Contains("Executable Authenticode status: $authenticodeStatus`n", [StringComparison]::Ordinal)) {
        Fail 'executable Authenticode status differs from the build manifest'
    }
    $artifactFiles = @($artifactEntries | Where-Object { -not $_.IsDirectory } | ForEach-Object { $_.FullPath })
    Assert-NoBuildRunnerPaths $artifactFiles
    $unpackedBytes = [int64] 0
    foreach ($artifactFile in $artifactFiles) {
        $unpackedBytes += ([IO.FileInfo] $artifactFile).Length
    }
    if ($unpackedBytes -le 0) {
        Fail 'unpacked regular-file byte count is empty'
    }

    $workRoot = [IO.Path]::Combine($ScratchRoot, 'acceptance work with spaces')
    [IO.Directory]::CreateDirectory($workRoot) | Out-Null
    $versionResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @('--version') -WorkingDirectory $workRoot
    Assert-ProcessResult $versionResult 0 "AttaLambda $productVersion`n" '' 'packaged version'
    $firstStartupMilliseconds = $versionResult.Milliseconds
    $helpResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @('--help') -WorkingDirectory $workRoot
    Assert-ProcessResult $helpResult 0 "Usage:`n  attalambda FILE.attl`n  attalambda --help`n  attalambda --version`n" '' 'packaged help'
    $helloResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @('examples\hello.attl') -WorkingDirectory $firstRoot
    Assert-ProcessResult $helloResult 0 "Hello from AttaLambda.`n" '' 'guide hello'
    $guideSource = [IO.Path]::Combine($firstRoot, 'my-program.attl')
    Write-LfUtf8 $guideSource "#lang attalambda`n`n(stdout `"My first AttaLambda program.\n`")`n"
    $guideResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @('my-program.attl') -WorkingDirectory $firstRoot
    Assert-ProcessResult $guideResult 0 "My first AttaLambda program.`n" '' 'guide custom program'
    $misuseResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @() -WorkingDirectory $workRoot
    Assert-ProcessResult $misuseResult 64 '' "AttaLambda: expected attalambda FILE.attl, attalambda --help, or attalambda --version`n" 'command misuse'
    $extensionResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @('missing.rkt') -WorkingDirectory $workRoot
    Assert-ProcessResult $extensionResult 65 '' "AttaLambda: `"missing.rkt`": source file name must end in lowercase .attl`n" 'wrong extension'
    $missingResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @('missing.attl') -WorkingDirectory $workRoot
    Assert-ProcessResult $missingResult 66 '' "AttaLambda: `"missing.attl`": source file was not found`n" 'missing source'

    $generatedDirectory = [IO.Path]::Combine($ScratchRoot, 'generated source path with spaces')
    [IO.Directory]::CreateDirectory($generatedDirectory) | Out-Null
    $generatedSource = [IO.Path]::Combine($generatedDirectory, 'generated-after-packaging.attl')
    Write-LfUtf8 $generatedSource "#lang attalambda`n`n(stdout `"Generated after packaging.\n`")`n"
    $generatedResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @($generatedSource) -WorkingDirectory $workRoot
    Assert-ProcessResult $generatedResult 0 "Generated after packaging.`n" '' 'generated source'

    $decoyRoot = [IO.Path]::Combine($ScratchRoot, 'decoy-collections')
    $decoyReaderDirectory = [IO.Path]::Combine($decoyRoot, 'attalambda', 'lang')
    [IO.Directory]::CreateDirectory($decoyReaderDirectory) | Out-Null
    Write-LfUtf8 ([IO.Path]::Combine($decoyReaderDirectory, 'reader.rkt')) "this external reader must never be loaded`n"
    $decoyResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @($generatedSource) -WorkingDirectory $workRoot -Environment @{ PLTCOLLECTS = $decoyRoot }
    Assert-ProcessResult $decoyResult 0 "Generated after packaging.`n" '' 'embedded-language precedence run'

    $stdoutWork = [IO.Path]::Combine($ScratchRoot, 'stdout work')
    [IO.Directory]::CreateDirectory($stdoutWork) | Out-Null
    $stdoutResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @([IO.Path]::Combine($firstRoot, 'examples', 'stdout.attl')) -WorkingDirectory $stdoutWork
    Assert-ProcessResult $stdoutResult 0 "Hello from AttaLambda.`n" '' 'stdout example'

    $fileWork = [IO.Path]::Combine($ScratchRoot, 'file work')
    [IO.Directory]::CreateDirectory($fileWork) | Out-Null
    $fileResult = Invoke-CapturedProcess -Executable $attalambda -Arguments @([IO.Path]::Combine($firstRoot, 'examples', 'file-round-trip.attl')) -WorkingDirectory $fileWork
    Assert-ProcessResult $fileResult 0 "AttaLambda file round trip.`n" '' 'file round trip'
    $roundTripPath = [IO.Path]::Combine($fileWork, 'attalambda-round-trip.txt')
    Assert-RegularNonsymlinkFile $roundTripPath 'file round-trip output'
    if ([IO.File]::ReadAllText($roundTripPath) -cne "AttaLambda file round trip.`n") {
        Fail 'packaged file round trip wrote the wrong bytes'
    }

    $httpWork = [IO.Path]::Combine($ScratchRoot, 'http work')
    [IO.Directory]::CreateDirectory($httpWork) | Out-Null
    Invoke-HttpAcceptance $attalambda ([IO.Path]::Combine($firstRoot, 'examples', 'http-server.attl')) $httpWork

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData) -or -not [IO.Directory]::Exists($localAppData)) {
        Fail 'consumer LocalApplicationData directory is unavailable for cross-drive relocation'
    }
    $RelocatedParent = [IO.Path]::Combine($localAppData, "AttaLambda relocated consumer $([Guid]::NewGuid().ToString('N')) path with spaces")
    $secondRoot = [IO.Path]::Combine($RelocatedParent, $artifactRootName)
    if ([IO.Path]::GetPathRoot($firstRoot).Equals([IO.Path]::GetPathRoot($secondRoot), [StringComparison]::OrdinalIgnoreCase)) {
        Fail 'consumer could not prove relocation to a different drive'
    }
    [IO.Directory]::CreateDirectory($RelocatedParent) | Out-Null
    Copy-SafeTree $firstRoot $secondRoot
    Remove-Item -LiteralPath $firstRoot -Recurse -Force
    if ([IO.Directory]::Exists($firstRoot)) {
        Fail 'first extracted tree still exists after relocation'
    }
    $attalambda = [IO.Path]::Combine($secondRoot, 'bin', 'attalambda.exe')
    $relocatedVersion = Invoke-CapturedProcess -Executable $attalambda -Arguments @('--version') -WorkingDirectory $workRoot
    Assert-ProcessResult $relocatedVersion 0 "AttaLambda $productVersion`n" '' 'relocated version'
    $relocatedSource = Invoke-CapturedProcess -Executable $attalambda -Arguments @($generatedSource) -WorkingDirectory $workRoot
    Assert-ProcessResult $relocatedSource 0 "Generated after packaging.`n" '' 'relocated source'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    [Console]::Out.WriteLine("consumer_windows_caption=$($os.Caption)")
    [Console]::Out.WriteLine("consumer_windows_version=$($os.Version)")
    [Console]::Out.WriteLine("consumer_windows_build=$($os.BuildNumber)")
    [Console]::Out.WriteLine("consumer_architecture=x86_64")
    [Console]::Out.WriteLine('consumer_racket_command=absent')
    [Console]::Out.WriteLine('consumer_raco_command=absent')
    [Console]::Out.WriteLine('consumer_checkout=absent')
    [Console]::Out.WriteLine("archive_sha256=$expectedDigest")
    [Console]::Out.WriteLine("compressed_bytes=$(([IO.FileInfo] $archivePath).Length)")
    [Console]::Out.WriteLine("unpacked_regular_file_bytes=$unpackedBytes")
    [Console]::Out.WriteLine("artifact_files=$($artifactFiles.Count)")
    [Console]::Out.WriteLine("pe_files=$($peFiles.Count)")
    [Console]::Out.WriteLine("system_dlls=$($actualSystem -join ',')")
    [Console]::Out.WriteLine("authenticode_status=$authenticodeStatus")
    [Console]::Out.WriteLine('guide_workflow=passed')
    [Console]::Out.WriteLine('relocation_drives=different')
    [Console]::Out.WriteLine('relocation=passed')
    [Console]::Out.WriteLine("first_startup_milliseconds=$firstStartupMilliseconds")
    [Console]::Out.WriteLine("relocated_startup_milliseconds=$($relocatedVersion.Milliseconds)")
    Write-Output 'consumer_acceptance=passed'
    $Succeeded = $true
}
catch {
    [Console]::Error.WriteLine("$ProgramName`: $($_.Exception.Message)")
}
finally {
    if ($null -ne $ScratchRoot -and [IO.Directory]::Exists($ScratchRoot)) {
        $scratchName = [IO.Path]::GetFileName($ScratchRoot)
        if ($scratchName.StartsWith('attalambda-windows-consumer-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $ScratchRoot -Recurse -Force
        }
    }
    if ($null -ne $RelocatedParent -and [IO.Directory]::Exists($RelocatedParent)) {
        $relocatedName = [IO.Path]::GetFileName($RelocatedParent)
        if ($relocatedName.StartsWith('AttaLambda relocated consumer ', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $RelocatedParent -Recurse -Force
        }
    }
}

if (-not $Succeeded) {
    exit 2
}
exit 0
