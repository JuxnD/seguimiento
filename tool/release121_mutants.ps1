param([string]$Flutter='C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat')
$ErrorActionPreference='Stop'
$qaRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$qaRunId=Get-Date -Format 'yyyyMMdd-HHmmss'
$qaHead=(git -C $qaRepo rev-parse HEAD).Trim()
$qaUtf8=New-Object System.Text.UTF8Encoding($false)
$qaInventory=@(
 @{id='frozen-caller';file='lib/features/training/training_screen.dart';old='s.effectiveDay == null ? (s.light ? lightVersion(adjusted) : adjusted) : thawGuidedDay(s.effectiveDay!)';new='(s.light ? lightVersion(adjusted) : adjusted)';test=@('caller resume usa snapshot efectivo tras lumbar y recupera evento de BD tras crash','snapshot con mapa efectivo malformado no tumba la pantalla')},
 @{id='legacy-caller';file='lib/features/training/training_screen.dart';old="withPlanche(deloaded, parseDay(s.date), v3,`n          enabled:";new="withV31Blocks(deloaded, parseDay(s.date), v3,`n          planche:";test='legado1.20 conserva secuencia e indice sin agregar escalera; guion malformado se descarta'},
 @{id='advice-reads';file='lib/data/repositories/ladder_repository.dart';old='readsFrom: {db.sessions, db.sessionSets, db.exercises, db.ladderStates, db.planVersions}';new='readsFrom: {db.exercises, db.ladderStates, db.planVersions}';test='consumer advice cambia tras guardar editar y borrar sin reiniciar'}
)
$qaResults=@()
$qaRestores=@()
$qaAttempted=0
$qaPrimaryError=$null
$qaCleanupError=$null
$qaGreens=1..3|ForEach-Object { $qaGreenPath=Join-Path $env:TEMP "seguimiento-121-final-focused-$_.log"; if(-not(Test-Path -LiteralPath $qaGreenPath)){throw "Falta verde habilitante: $qaGreenPath"}; $qaGreenText=[IO.File]::ReadAllText($qaGreenPath); if($qaGreenText -notmatch '\+29: All tests passed!'){throw "Verde habilitante no coincide: $qaGreenPath"}; @{path=$qaGreenPath;sha256=(Get-FileHash -LiteralPath $qaGreenPath -Algorithm SHA256).Hash.ToLowerInvariant();head=$qaHead;expectedPassed=29} }
Push-Location $qaRepo
try {
 foreach($qaMutation in $qaInventory) {
  $qaPath=Join-Path $qaRepo $qaMutation.file
  $qaBytes=[IO.File]::ReadAllBytes($qaPath)
  $qaText=$qaUtf8.GetString($qaBytes).Replace("`r`n","`n")
  if(([regex]::Matches($qaText,[regex]::Escape($qaMutation.old))).Count -ne 1){throw "Target inexistente/ambiguo: $($qaMutation.id)"}
  $qaLog=Join-Path $env:TEMP "seguimiento-121-mutant-$qaRunId-$($qaMutation.id).log"
  $qaAttempted++
  try {
   [IO.File]::WriteAllText($qaPath,$qaText.Replace($qaMutation.old,$qaMutation.new),$qaUtf8)
   & $Flutter test --no-pub test/ui/release121_flows_test.dart --reporter expanded *> $qaLog
   $qaExit=$LASTEXITCODE
   $qaOutput=[IO.File]::ReadAllText($qaLog).Replace("`r`n","`n")
   $qaFailures=[regex]::Matches($qaOutput,'(?m)^\d\d:\d\d \+\d+ -\d+: (.*?) \[E\]$')
   $qaExpected=@($qaMutation.test)
   $qaActual=@($qaFailures|ForEach-Object{$_.Groups[1].Value})
   $qaDiff=@(Compare-Object ($qaExpected|Sort-Object) ($qaActual|Sort-Object))
   $qaPassed=6-$qaExpected.Count
   $qaFinalPattern='\+'+$qaPassed+' -'+$qaExpected.Count+':'
   $qaExact=$qaExit -eq 1 -and $qaFailures.Count -eq $qaExpected.Count -and $qaDiff.Count -eq 0 -and $qaOutput -match $qaFinalPattern -and $qaOutput -match 'Expected:' -and $qaOutput -notmatch 'Compilation failed|Timer is still pending|PathAccessException|TimeoutException'
   $qaResults+=@{id=$qaMutation.id;test=$qaMutation.test;exit=$qaExit;exact=$qaExact;log=$qaLog}
   if(-not $qaExact){throw "Mutante sin veredicto exacto: $($qaMutation.id). Ver $qaLog"}
   Write-Output "$($qaMutation.id): $qaPassed pasan, $($qaExpected.Count) fallan exactamente por contratos esperados"
  } catch { $qaPrimaryError=$_.Exception.Message; throw } finally {
   try {
   [IO.File]::WriteAllBytes($qaPath,$qaBytes)
   $qaSha=[System.Security.Cryptography.SHA256]::Create()
   $qaOriginal=[BitConverter]::ToString($qaSha.ComputeHash($qaBytes))
   $qaRestored=[BitConverter]::ToString($qaSha.ComputeHash([IO.File]::ReadAllBytes($qaPath)))
   $qaSha.Dispose()
   $qaRestores+=@{mutation=$qaMutation.id;path=$qaPath;originalSha256=$qaOriginal.Replace('-','').ToLowerInvariant();restoredSha256=$qaRestored.Replace('-','').ToLowerInvariant();matches=($qaOriginal -eq $qaRestored)}
   if($qaOriginal -ne $qaRestored){throw "No se restauraron bytes originales: $qaPath"}
   } catch { $qaCleanupError=$_.Exception.Message; if($null -eq $qaPrimaryError){throw} }
  }
 }
} finally {
 Pop-Location
 $qaReceipt=Join-Path $env:TEMP "seguimiento-121-mutants-$qaRunId.json"
 @{head=$qaHead;runId=$qaRunId;configuration=@{flutter=$Flutter;test='test/ui/release121_flows_test.dart';externalCalls=$false};greens=$qaGreens;inventory=$qaInventory|ForEach-Object{$_.id};results=$qaResults;restores=$qaRestores;primaryError=$qaPrimaryError;cleanupError=$qaCleanupError;sourceRestored=($qaAttempted -gt 0 -and $qaRestores.Count -eq $qaAttempted -and @($qaRestores|Where-Object{-not $_.matches}).Count -eq 0 -and $null -eq $qaCleanupError)}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $qaReceipt -Encoding UTF8
 Write-Output $qaReceipt
}
