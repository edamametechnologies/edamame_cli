$packageName = 'edamame-cli'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$fileFullPath = Join-Path $toolsDir "edamame_cli.exe"

# Remove the binary file if it exists
if (Test-Path $fileFullPath) {
    Remove-Item $fileFullPath -Force -ErrorAction SilentlyContinue
}

# Uninstall-ChocolateyPackage will handle removing the shim
Uninstall-ChocolateyPackage -PackageName $packageName



