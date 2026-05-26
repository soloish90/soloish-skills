param(
    [string[]]$Skill = @(),
    [switch]$AllSkills,
    [string[]]$Target = @(),
    [string]$Repo = "soloish90/soloish-skills",
    [string]$Ref = "main",
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    @"
Install skills from soloish-skills.

Usage:
  .\install.ps1 [options]

Options:
  -Skill NAME       Skill to install. Repeatable.
  -AllSkills        Install every skill.
  -Target NAME      codex, codex-legacy, claude, or all. Repeatable.
  -Repo OWNER/REPO  GitHub repo. Default: soloish90/soloish-skills.
  -Ref REF          Git ref. Default: main.
  -Yes              Replace existing installed skills without prompting.
  -DryRun           Show what would be installed.
  -Help             Show help.
"@
}

if ($Help) {
    Show-Usage
    exit 0
}

function Split-Items([string[]]$Items) {
    $result = @()
    foreach ($item in $Items) {
        foreach ($part in ($item -split ",")) {
            $trimmed = $part.Trim()
            if ($trimmed) { $result += $trimmed }
        }
    }
    $result | Select-Object -Unique
}

function Get-TargetDir([string]$Name) {
    switch ($Name) {
        "codex" { Join-Path $HOME ".agents/skills" }
        "codex-legacy" {
            if ($env:CODEX_HOME) {
                Join-Path $env:CODEX_HOME "skills"
            } else {
                Join-Path $HOME ".codex/skills"
            }
        }
        "claude" { Join-Path $HOME ".claude/skills" }
        default { throw "Unknown target: $Name" }
    }
}

function Get-TargetLabel([string]$Name) {
    switch ($Name) {
        "codex" { "Codex" }
        "codex-legacy" { "Codex legacy" }
        "claude" { "Claude Code" }
        default { throw "Unknown target: $Name" }
    }
}

function Prompt-ChoiceList([string]$Title, [string[]]$Options, [string[]]$Default) {
    Write-Host $Title
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $Options[$i])
    }
    $defaultText = $Default -join ","
    $answer = Read-Host "Choose by number/name, comma-separated, or Enter for $defaultText"
    if (-not $answer.Trim()) {
        return $Default
    }

    $selected = @()
    foreach ($choice in ($answer -split ",")) {
        $choice = $choice.Trim()
        if (-not $choice) { continue }
        if ($choice -match "^\d+$") {
            $index = [int]$choice - 1
            if ($index -lt 0 -or $index -ge $Options.Count) {
                throw "Invalid selection: $choice"
            }
            $selected += $Options[$index]
        } else {
            $selected += $choice
        }
    }
    $selected | Select-Object -Unique
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("soloish-skills-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    $zipPath = Join-Path $temp "repo.zip"
    $archiveUrl = "https://github.com/$Repo/archive/refs/heads/$Ref.zip"
    try {
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        $archiveUrl = "https://github.com/$Repo/archive/$Ref.zip"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
    }

    Expand-Archive -Path $zipPath -DestinationPath $temp -Force
    $repoRoot = Get-ChildItem -Path $temp -Directory | Where-Object { $_.Name -ne "__MACOSX" } | Select-Object -First 1
    if (-not $repoRoot) { throw "Could not find extracted repo root." }

    $skillsRoot = Join-Path $repoRoot.FullName "skills"
    if (-not (Test-Path $skillsRoot)) {
        throw "No skills directory found in $Repo@$Ref"
    }

    $availableSkills = Get-ChildItem -Path $skillsRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } |
        ForEach-Object { $_.Name } |
        Sort-Object

    if (-not $availableSkills) {
        throw "No skills found in $Repo@$Ref"
    }

    if ($AllSkills) {
        $selectedSkills = $availableSkills
    } elseif ($Skill.Count -gt 0) {
        $selectedSkills = Split-Items $Skill
    } else {
        $selectedSkills = Prompt-ChoiceList "Skills:" $availableSkills $availableSkills
    }

    foreach ($name in $selectedSkills) {
        if (-not (Test-Path (Join-Path $skillsRoot "$name/SKILL.md"))) {
            throw "Unknown skill: $name"
        }
    }

    if ($Target.Count -gt 0) {
        $selectedTargets = @()
        foreach ($name in (Split-Items $Target)) {
            if ($name -eq "all") {
                $selectedTargets += "codex", "claude"
            } else {
                $selectedTargets += $name
            }
        }
        $selectedTargets = $selectedTargets | Select-Object -Unique
    } else {
        $selectedTargets = Prompt-ChoiceList "Targets:" @("codex", "claude", "codex-legacy") @("codex", "claude")
    }

    foreach ($targetName in $selectedTargets) {
        [void](Get-TargetDir $targetName)
    }

    $existing = @()
    foreach ($targetName in $selectedTargets) {
        $root = Get-TargetDir $targetName
        foreach ($skillName in $selectedSkills) {
            $dest = Join-Path $root $skillName
            if (Test-Path $dest) { $existing += $dest }
        }
    }

    if ($existing.Count -gt 0 -and -not $Yes -and -not $DryRun) {
        Write-Host "These installed skills will be replaced:"
        $existing | ForEach-Object { Write-Host "  $_" }
        $answer = Read-Host "Replace them? [y/N]"
        if ($answer -notin @("y", "Y", "yes", "YES")) {
            Write-Host "Install cancelled."
            exit 1
        }
    }

    foreach ($targetName in $selectedTargets) {
        $root = Get-TargetDir $targetName
        $label = Get-TargetLabel $targetName
        Write-Host "${label}: $root"
        foreach ($skillName in $selectedSkills) {
            $source = Join-Path $skillsRoot $skillName
            $dest = Join-Path $root $skillName
            if ($DryRun) {
                Write-Host "Would install $skillName -> $dest"
            } else {
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                if (Test-Path $dest) {
                    Remove-Item -Recurse -Force $dest
                }
                Copy-Item -Recurse -Force $source $dest
                Write-Host "Installed $skillName -> $dest"
            }
        }
    }

    Write-Host "Done."
} finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}
