[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Command,
    [string]$CommandLine
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ((-not $Command -or $Command.Count -eq 0) -and [string]::IsNullOrWhiteSpace($CommandLine)) {
    throw "Usage: .\\Scripts\\with-msvc-env.ps1 <command> [args...] or -CommandLine '<command line>'"
}

function Get-VsInstallationPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -eq 0 -and $path) {
            return ($path | Select-Object -First 1).Trim()
        }
    }

    $fallbacks = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community",
        "C:\Program Files\Microsoft Visual Studio\18\Community"
    )

    foreach ($candidate in $fallbacks) {
        if (Test-Path (Join-Path $candidate "Common7\Tools\VsDevCmd.bat")) {
            return $candidate
        }
    }

    return $null
}

$installationPath = Get-VsInstallationPath
if (-not $installationPath) {
    throw "Could not find a Visual Studio installation with the MSVC C++ toolset. Install Visual Studio Build Tools with 'Desktop development with C++'."
}

$vsDevCmd = Join-Path $installationPath "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsDevCmd)) {
    throw "Could not find VsDevCmd.bat under '$installationPath'."
}

$envDump = & cmd.exe /d /s /c "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to load the MSVC build environment from '$vsDevCmd'."
}

foreach ($line in $envDump) {
    $separator = $line.IndexOf("=")
    if ($separator -le 0) {
        continue
    }

    $name = $line.Substring(0, $separator)
    $value = $line.Substring($separator + 1)
    Set-Item -Path "Env:$name" -Value $value
}

$bindgenIncludeArgs = @()
foreach ($includePath in ($env:INCLUDE -split ";")) {
    if (-not [string]::IsNullOrWhiteSpace($includePath)) {
        $normalizedPath = $includePath.Replace("\", "/")
        $bindgenIncludeArgs += "-I`"$normalizedPath`""
    }
}

if ($bindgenIncludeArgs.Count -gt 0) {
    $existingArgs = $env:BINDGEN_EXTRA_CLANG_ARGS
    $env:BINDGEN_EXTRA_CLANG_ARGS = (($bindgenIncludeArgs -join " ") + " " + $existingArgs).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {
    & cmd.exe /d /s /c $CommandLine
    exit $LASTEXITCODE
}

$commandName = $Command[0]
$commandArgs = if ($Command.Count -gt 1) { $Command[1..($Command.Count - 1)] } else { @() }

& $commandName @commandArgs
exit $LASTEXITCODE
