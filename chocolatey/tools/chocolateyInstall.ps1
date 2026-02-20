$packageName = 'edamame-cli'
$packageVersion = '1.0.7'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url64 = "https://github.com/edamametechnologies/edamame_cli/releases/download/v$packageVersion/edamame_cli-$packageVersion-x86_64-pc-windows-msvc.exe"
$checksum64 = '969ca28f90a53ddb909d6a4b1b527afa797c6bb3ea782ad745d55bf0324f3e97'

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



