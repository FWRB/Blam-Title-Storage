#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# === Prompt user for input ===
$configDir = Read-Host 'Enter path to config directory'
$oldBlfCli = Read-Host 'Enter path to old blf_cli tool'
$newBlfCli = Read-Host 'Enter path to new blf_cli tool'
$title = Read-Host 'Enter game title (e.g., Halo 3)'
$version = Read-Host 'Enter build version (e.g., 12070.08.09.05.2031.halo3_ship)'

$configDir = (Resolve-Path -LiteralPath $configDir).Path
$oldBlfCli = (Resolve-Path -LiteralPath $oldBlfCli).Path
$newBlfCli = (Resolve-Path -LiteralPath $newBlfCli).Path

Write-Host "Upgrading configuration for $title version $version"
Write-Host "Config path: $configDir"

$buildDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $buildDir | Out-Null
Write-Host "Using temporary build_dir: $buildDir"

try {
    # Step 1: Build binaries from configuration
    Write-Host '== Step 1: Building binary files from configuration =='
    & $oldBlfCli title-storage build $configDir $buildDir $title $version
    if ($LASTEXITCODE -ne 0) { throw "blf_cli exited with code $LASTEXITCODE" }
    Write-Host '== Done building binary files =='

    function Export-Variants {
        param([string]$VariantType)

        Get-ChildItem -LiteralPath $configDir -Recurse -Directory -Filter $VariantType | ForEach-Object {
            $inputDir = $_.FullName
            $hopperFolder = $_.Parent.Name
            $outputDir = Join-Path (Join-Path $buildDir $hopperFolder) $VariantType
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            Write-Host "Exporting variants to $outputDir"

            Get-ChildItem -LiteralPath $inputDir -Filter '*.json' | ForEach-Object {
                $jsonFile = $_.FullName
                $filename = $_.BaseName
                $outputFile = Join-Path $outputDir "$filename.bin"
                Write-Host "Exporting $jsonFile"
                & $oldBlfCli title-storage export-variant $jsonFile $outputFile $title $version
                if ($LASTEXITCODE -ne 0) { throw "blf_cli exited with code $LASTEXITCODE" }
            }
        }
    }

    # Step 2: Export game and map variants
    Write-Host '== Step 2: Exporting game and map variants =='
    Export-Variants 'map_variants'
    Export-Variants 'game_variants'
    Write-Host '== Done exporting variants =='

    # Step 3: Build configuration from binary files
    Write-Host '== Step 3: Building configuration from binary files =='
    & $newBlfCli title-storage build-config $buildDir $configDir $title $version
    if ($LASTEXITCODE -ne 0) { throw "blf_cli exited with code $LASTEXITCODE" }
    Write-Host '== Done building configuration =='

    function Import-Variants {
        param([string]$VariantType)

        Get-ChildItem -LiteralPath $buildDir -Directory | ForEach-Object {
            $hopperFolder = $_.Name
            $variantPath = Join-Path $_.FullName $VariantType

            if (Test-Path -LiteralPath $variantPath -PathType Container) {
                Write-Host "Processing $hopperFolder/$VariantType"

                Get-ChildItem -LiteralPath $variantPath -Filter '*.bin' | ForEach-Object {
                    $binFile = $_.FullName
                    $hopperConfigDir = Join-Path $configDir $hopperFolder
                    Write-Host "Importing $hopperConfigDir"
                    & $newBlfCli title-storage import-variant $hopperConfigDir $binFile $title $version
                    if ($LASTEXITCODE -ne 0) { throw "blf_cli exited with code $LASTEXITCODE" }
                }
            }
        }
    }

    # Step 4: Import variants back into config
    Write-Host '== Step 4: Importing variants into configuration =='
    Import-Variants 'map_variants'
    Import-Variants 'game_variants'
    Write-Host '== Done importing variants =='
}
finally {
    Write-Host 'Cleaning up temporary build_dir...'
    if (Test-Path -LiteralPath $buildDir) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }
}
