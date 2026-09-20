function Get-CommonToolInstallBase {
    $relativeBases = @(
        "APP",
        "App",
        "tools",
        "Tools",
        "Program Files",
        "Program Files (x86)",
        "MentorGraphics"
    )

    $bases = @()
    $driveRoots = Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Root -match '^[A-Za-z]:\\$'
    }
    foreach ($driveRoot in $driveRoots) {
        foreach ($relativeBase in $relativeBases) {
            $candidate = Join-Path $driveRoot.Root $relativeBase
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $bases += (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    return $bases | Select-Object -Unique
}

function Resolve-ModelSimBin {
    param(
        [string]$PreferredPath
    )

    $candidates = @()
    if ($PreferredPath) {
        if (Test-Path -LiteralPath $PreferredPath -PathType Leaf) {
            $candidates += Split-Path $PreferredPath -Parent
        } else {
            $candidates += $PreferredPath
        }
    }

    $modelSimCommand = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if ($modelSimCommand) {
        $candidates += Split-Path $modelSimCommand.Source -Parent
    }

    foreach ($base in Get-CommonToolInstallBase) {
        $candidates += Join-Path $base "win64"
        $toolDirectories = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)modelsim|questa|mentor' }
        foreach ($toolDirectory in $toolDirectories) {
            $candidates += $toolDirectory.FullName
            $candidates += Join-Path $toolDirectory.FullName "win64"
            $versionDirectories = Get-ChildItem -LiteralPath $toolDirectory.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($versionDirectory in $versionDirectories) {
                $candidates += $versionDirectory.FullName
                $candidates += Join-Path $versionDirectory.FullName "win64"
            }
        }
    }

    $resolved = $candidates | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ "vsim.exe") -PathType Leaf
    } | Select-Object -First 1
    if (-not $resolved) {
        throw "ModelSim not found. Set MODELSIM_BIN or pass -ModelSimBin."
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}

function Resolve-TdRoot {
    param(
        [string]$PreferredPath,
        [switch]$RequirePh1SimulationModels
    )

    $candidates = @()
    if ($PreferredPath) {
        if ((Split-Path $PreferredPath -Leaf) -eq "td_commands_prompt.exe") {
            $candidates += Split-Path (Split-Path $PreferredPath -Parent) -Parent
        } else {
            $candidates += $PreferredPath
        }
    }

    $tdCommand = Get-Command td_commands_prompt.exe -ErrorAction SilentlyContinue
    if ($tdCommand) {
        $candidates += Split-Path (Split-Path $tdCommand.Source -Parent) -Parent
    }

    foreach ($base in Get-CommonToolInstallBase) {
        $searchParents = @($base, (Join-Path $base "Anlogic"))
        foreach ($searchParent in $searchParents) {
            if (-not (Test-Path -LiteralPath $searchParent -PathType Container)) {
                continue
            }
            $tdDirectories = Get-ChildItem -LiteralPath $searchParent -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)^TD_' }
            $candidates += $tdDirectories.FullName
        }
    }

    $resolved = $candidates | Where-Object {
        $hasBatchTool = Test-Path -LiteralPath (Join-Path $_ "bin\td_commands_prompt.exe") -PathType Leaf
        $hasModels = Test-Path -LiteralPath (Join-Path $_ "sim_release\ph1") -PathType Container
        $hasBatchTool -and (-not $RequirePh1SimulationModels -or $hasModels)
    } | Select-Object -First 1
    if (-not $resolved) {
        throw "TD installation not found. Set TD_ROOT or pass -TdRoot."
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}
