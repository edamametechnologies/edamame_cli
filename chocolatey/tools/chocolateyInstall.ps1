$packageName = 'edamame-cli'
$packageVersion = '1.0.9'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url64 = "https://github.com/edamametechnologies/edamame_cli/releases/download/v$packageVersion/edamame_cli-$packageVersion-x86_64-pc-windows-msvc.exe"
$checksum64 = 'PLACEHOLDER_WILL_BE_SET_BY_CI'

# Download the standalone executable
$fileFullPath = Join-Path $toolsDir "edamame_cli.exe"
Get-ChocolateyWebFile -PackageName $packageName `
                      -FileFullPath $fileFullPath `
                      -Url64bit $url64 `
                      -Checksum64 $checksum64 `
                      -ChecksumType64 'sha256'

# Install-ChocolateyBinaryFile creates a shim so the executable is available in PATH
Install-BinFile -Name $packageName `
                -Path $fileFullPath



