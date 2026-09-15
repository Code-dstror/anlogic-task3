param(
    [string[]]$Manifest,
    [switch]$CompareOfficialSource
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Read-ManifestEntries {
    param([string]$ManifestPath)

    $resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
    $entries = @()
    foreach ($line in Get-Content -LiteralPath $resolvedManifest) {
        if (-not $line.Trim()) { continue }
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') {
            throw "Invalid SHA256SUMS line in ${resolvedManifest}: $line"
        }
        $entries += [pscustomobject]@{
            Expected = $Matches[1].ToLowerInvariant()
            Relative = $Matches[2].Replace('/', [IO.Path]::DirectorySeparatorChar)
        }
    }
    return $entries
}

function Assert-ExpectedHash {
    param(
        [string]$Path,
        [string]$Expected,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing ${Description}: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        throw "Hash mismatch for ${Description}: $Path"
    }
}

if (-not $Manifest) {
    $Manifest = @(
        (Join-Path $repo "fpga_rtl\vendor\anlogic_pcie_sgdma\SHA256SUMS.txt"),
        (Join-Path $repo "fpga_rtl\vendor\anlogic_soft_fifo_3_0\SHA256SUMS.txt")
    )
}

$checked = 0
foreach ($manifestPath in $Manifest) {
    $resolvedManifest = (Resolve-Path -LiteralPath $manifestPath).Path
    $baseDir = Split-Path $resolvedManifest -Parent
    foreach ($entry in Read-ManifestEntries -ManifestPath $resolvedManifest) {
        $target = Join-Path $baseDir $entry.Relative
        Assert-ExpectedHash -Path $target -Expected $entry.Expected -Description "vendor file"
        $checked++
    }
}

Write-Output "[vendor hashes] RESULT: PASS ($checked files)"

if ($CompareOfficialSource) {
    $officialPackage = Join-Path $repo "03_MLK_AFH03_AFC03"
    $officialProject = Join-Path $officialPackage `
        "03_course\07_异构方案\AFC03_IMX415_PCIE_X1\AFC03_IMX415_PCIE_X1\IMX415_PCIE_X1"
    if (-not (Test-Path -LiteralPath $officialProject)) {
        throw "Optional official source project is unavailable: $officialProject"
    }

    $pcieSnapshot = Join-Path $repo "fpga_rtl\vendor\anlogic_pcie_sgdma"
    $pcieManifest = Join-Path $pcieSnapshot "SHA256SUMS.txt"
    $sourceChecked = 0
    foreach ($entry in Read-ManifestEntries -ManifestPath $pcieManifest) {
        $relative = $entry.Relative
        if ($relative.StartsWith("al_ip\")) {
            $tail = $relative.Substring("al_ip\".Length)
            if ($tail -in @("al_pcie_ip.dat", "al_pcie_ip.txt")) {
                $tail = $tail.Replace("al_pcie_ip", "PH1_LOGIC_PCIE")
            }
            $source = Join-Path $officialProject (Join-Path "al_ip" $tail)
        } elseif ($relative.StartsWith("sgdma\src_enc\")) {
            $source = Join-Path $officialProject (Join-Path "uisrc\03_ip" $relative)
        } elseif ($relative -eq "sgdma\sgdma_subsys.v") {
            $source = Join-Path $officialProject "uisrc\03_ip\sgdma\sgdma_subsys.v"
        } elseif ($relative.StartsWith("sgdma\bridge\case_ep\")) {
            $tail = $relative.Substring("sgdma\bridge\case_ep\".Length)
            $source = Join-Path $officialProject `
                (Join-Path "uisrc\03_ip\sgdma\pcie_bridge\bridge_v1_ph1\case_ep" $tail)
        } elseif ($relative.StartsWith("sgdma\bridge\")) {
            $tail = $relative.Substring("sgdma\bridge\".Length)
            $source = Join-Path $officialProject `
                (Join-Path "uisrc\03_ip\sgdma\pcie_bridge\bridge_v1_ph1\al_pcie_if" $tail)
        } else {
            throw "No official-source mapping for PCIe snapshot file: $relative"
        }
        Assert-ExpectedHash -Path $source -Expected $entry.Expected -Description "official PCIe/SGDMA source"
        $sourceChecked++
    }

    $tdRoot = $env:TD_ROOT
    if (-not $tdRoot) { $tdRoot = $env:ANLOGIC_TD_ROOT }
    if (-not $tdRoot) { $tdRoot = $env:TD_INSTALL_DIR }
    if (-not $tdRoot) {
        throw "TD_ROOT, ANLOGIC_TD_ROOT, or TD_INSTALL_DIR is required for Soft FIFO source comparison."
    }
    $fifoSnapshot = Join-Path $repo "fpga_rtl\vendor\anlogic_soft_fifo_3_0"
    $fifoManifest = Join-Path $fifoSnapshot "SHA256SUMS.txt"
    $fifoSource = Join-Path $tdRoot "ip\depot\Soft_FIFO_3.0"
    foreach ($entry in Read-ManifestEntries -ManifestPath $fifoManifest) {
        $source = Join-Path $fifoSource $entry.Relative
        Assert-ExpectedHash -Path $source -Expected $entry.Expected -Description "installed Soft FIFO source"
        $sourceChecked++
    }

    Write-Output "[vendor origins] RESULT: PASS ($sourceChecked files)"
}
