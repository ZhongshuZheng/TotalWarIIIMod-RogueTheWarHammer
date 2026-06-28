[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)

$pythonExe = "D:\SoftWares\miniforge3\python.exe"
$luacExe = "D:\SoftWares\Lua\luac55.exe"
$generatorScript = Join-Path $scriptRoot "generate_stage_d_data.py"
$heroRewardMetadataScript = Join-Path $scriptRoot "update_hero_reward_metadata.py"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Missing Python interpreter: $pythonExe"
}

if (-not (Test-Path -LiteralPath $generatorScript)) {
    throw "Missing generator script: $generatorScript"
}

if (-not (Test-Path -LiteralPath $heroRewardMetadataScript)) {
    throw "Missing hero reward metadata script: $heroRewardMetadataScript"
}

Write-Host "[stage-d] Running generator..."
& $pythonExe $generatorScript

Write-Host "[stage-d] Updating hero reward metadata..."
& $pythonExe $heroRewardMetadataScript

$generatedLuaFiles = @(
    (Join-Path $repoRoot "script\campaign\mod\adamrogue\adamrogue_data_nodes.lua"),
    (Join-Path $repoRoot "script\campaign\mod\adamrogue\adamrogue_data_battle_pools.lua"),
    (Join-Path $repoRoot "script\campaign\mod\adamrogue\adamrogue_data_ancillaries.lua"),
    (Join-Path $repoRoot "script\campaign\mod\adamrogue\adamrogue_data_players.lua"),
    (Join-Path $repoRoot "script\campaign\mod\adamrogue\adamrogue_data_enemy_skills.lua")
)

$generatedLuaFiles += Get-ChildItem -LiteralPath (Join-Path $repoRoot "script\campaign\mod\adamrogue") -Filter "adamrogue_data_enemy_skills_*.lua" |
    Select-Object -ExpandProperty FullName

$generatedLuaFiles += @(
    (Join-Path $repoRoot "script\campaign\mod\adamrogue\adamrogue_enemy_skill_allocator.lua"),
    (Join-Path $repoRoot "script\campaign\mod\adamrogue_mvp.lua")
)

if (Test-Path -LiteralPath $luacExe) {
    Write-Host "[stage-d] Running luac syntax checks..."
    foreach ($luaFile in $generatedLuaFiles) {
        & $luacExe -p $luaFile
    }
    Write-Host "[stage-d] luac checks passed."
} else {
    Write-Warning "Skipping luac validation because the executable was not found: $luacExe"
}

Write-Host "[stage-d] Stage D data regeneration completed."
