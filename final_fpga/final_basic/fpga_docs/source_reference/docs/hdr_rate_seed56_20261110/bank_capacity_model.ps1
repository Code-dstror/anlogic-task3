[CmdletBinding()]
param(
    [int] $PeriodUs = 32997,
    [int] $CaptureUs = 30000,
    [int[]] $ServiceUs = @(19500, 16589, 16498, 15900),
    [int[]] $PhaseUs,
    [int] $WarmupGroups = 30,
    [int] $MeasuredGroups = 330
)

$ErrorActionPreference = 'Stop'
if ($null -eq $PhaseUs) {
    $PhaseUs = @(0, 100, 4000, ($PeriodUs - 100))
}
if ($PeriodUs -le 1000 -or $CaptureUs -le 2000 -or $WarmupGroups -lt 0 -or $MeasuredGroups -le 0) {
    throw 'Invalid capture or measurement interval.'
}

function Measure-TwoBankModel([int] $Phase, [int] $Service) {
    if ($Phase -lt 0 -or $Phase -ge $PeriodUs -or $Service -le 0) {
        throw 'Phase must be inside the period and service must be positive.'
    }
    $events = [System.Collections.Generic.List[object]]::new()
    for ($group = 0; $group -lt ($WarmupGroups + $MeasuredGroups); $group++) {
        foreach ($eye in 0, 1) {
            $start = [long] $group * $PeriodUs + $eye * $Phase
            $events.Add([pscustomobject] @{ At = $start; Kind = 1; Eye = $eye; Group = $group })
            $events.Add([pscustomobject] @{ At = $start + 1000; Kind = 2; Eye = $eye; Group = $group })
            $events.Add([pscustomobject] @{ At = $start + $CaptureUs - 1000; Kind = 0; Eye = $eye; Group = $group })
            $events.Add([pscustomobject] @{ At = $start + $CaptureUs; Kind = 0; Eye = $eye; Group = $group })
        }
    }
    $timeline = @($events | Sort-Object At, Kind, Eye)
    $eyes = foreach ($eye in 0, 1) {
        [pscustomobject] @{
            Pending = [System.Collections.Generic.List[object]]::new()
            Denied = [System.Collections.Generic.HashSet[int]]::new()
            Jobs = 0
            LostGroups = 0
            BeginRejects = 0
            MaxReadyWaitUs = 0L
            MaxBankHoldUs = 0L
        }
    }

    $preferred = 0
    $index = 0
    $active = $null
    $releaseAt = [long]::MaxValue
    while ($index -lt $timeline.Count -or $null -ne $active) {
        $nextInputAt = if ($index -lt $timeline.Count) { $timeline[$index].At } else { [long]::MaxValue }
        $now = [Math]::Min($nextInputAt, $releaseAt)
        if ($releaseAt -eq $now) {
            $eyes[$active.Eye].Pending.RemoveAt(0)
            $preferred = 1 - $active.Eye
            $active = $null
            $releaseAt = [long]::MaxValue
        }
        while ($index -lt $timeline.Count -and $timeline[$index].At -eq $now) {
            $event = $timeline[$index]
            $index++
            $state = $eyes[$event.Eye]
            $measured = $event.Group -ge $WarmupGroups
            switch ($event.Kind) {
                0 {
                    foreach ($pending in $state.Pending) {
                        if ($pending.Group -eq $event.Group) {
                            $pending.Finished++
                            if ($pending.Finished -eq 2) {
                                $pending.ReadyAt = $now
                            }
                            break
                        }
                    }
                }
                1 {
                    if ($state.Pending.Count -eq 2) {
                        [void] $state.Denied.Add($event.Group)
                        if ($measured) {
                            $state.LostGroups++
                            $state.BeginRejects++
                        }
                    } else {
                        $state.Pending.Add([pscustomobject] @{
                            Eye = $event.Eye
                            Group = $event.Group
                            BeginAt = $now
                            Finished = 0
                            ReadyAt = $null
                        })
                    }
                }
                2 {
                    if ($state.Denied.Remove($event.Group) -and $measured) {
                        $state.BeginRejects++
                    }
                }
            }
        }
        if ($null -eq $active) {
            foreach ($eye in $preferred, (1 - $preferred)) {
                $state = $eyes[$eye]
                if ($state.Pending.Count -eq 0 -or $null -eq $state.Pending[0].ReadyAt) {
                    continue
                }
                $active = $state.Pending[0]
                $releaseAt = $now + $Service
                if ($active.Group -ge $WarmupGroups) {
                    $state.Jobs++
                    $state.MaxReadyWaitUs = [Math]::Max($state.MaxReadyWaitUs, $now - $active.ReadyAt)
                    $state.MaxBankHoldUs = [Math]::Max($state.MaxBankHoldUs, $releaseAt - $active.BeginAt)
                }
                break
            }
        }
    }
    foreach ($eye in $eyes) {
        if ($eye.Jobs + $eye.LostGroups -ne $MeasuredGroups -or $eye.BeginRejects -ne 2 * $eye.LostGroups) {
            throw 'The measured group and member ledgers disagree.'
        }
    }
    [pscustomobject] @{
        PhaseUs = $Phase
        ServiceUs = $Service
        Jobs = @($eyes.Jobs)
        BeginRejects = @($eyes.BeginRejects)
        MaxReadyWaitUs = @($eyes.MaxReadyWaitUs)
        MaxBankHoldUs = @($eyes.MaxBankHoldUs)
    }
}

foreach ($service in $ServiceUs) {
    foreach ($phase in $PhaseUs) {
        Measure-TwoBankModel -Phase $phase -Service $service
    }
}
