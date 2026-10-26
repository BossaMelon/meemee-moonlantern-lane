#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$ReportDirectory,
    [ValidateRange(10, 900)][int]$GateTimeoutSeconds = 420
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
if (-not $IsWindows) { throw 'This supervisor requires Windows; no Windows verification was executed.' }
$checkout = Split-Path $PSScriptRoot -Parent
$tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$ownedRoot = Join-Path $tempBase ('W01 月灯巷 ' + [guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $ownedRoot) { throw 'Owned temporary directory must be fresh.' }
[IO.Directory]::CreateDirectory($ownedRoot) | Out-Null
if (-not $ReportDirectory) { $ReportDirectory = Join-Path $ownedRoot 'reports' }
$ReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $ReportDirectory) { throw 'Evidence directory must be fresh; never overwrite/reuse.' }
[IO.Directory]::CreateDirectory($ReportDirectory) | Out-Null
$executions = [Collections.Generic.List[object]]::new()

. (Join-Path $PSScriptRoot 'windows_process.ps1')

function Write-Json($Path, $Value) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 100), $utf8)
}
function Read-Log($Path) {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($stream,$utf8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Assert-Archive($Path, [long]$Size, $Sha) {
    $file = Get-Item -LiteralPath $Path
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Archive must be a regular file.' }
    if ($file.Length -ne $Size) { throw 'Archive size mismatch.' }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha) { throw 'Archive SHA256 mismatch.' }
}
function Invoke-Owned($Exe, [string[]]$Arguments, $Working, [int]$Seconds, $Label, $EngineLog = '') {
    if ($Exe -isnot [string] -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Expected one existing executable path: $Label" }
    $out = Join-Path $ReportDirectory ($Label + '-stdout.log')
    $err = Join-Path $ReportDirectory ($Label + '-stderr.log')
    $entry = [ordered]@{label=$Label; executable=$Exe; arguments=$Arguments; working_directory=$Working; process=$null; engine_error_logged=$false}
    $executions.Add($entry)
    Write-Json (Join-Path $ReportDirectory 'executions.json') $executions.ToArray()
    $result = [W01Process]::Run($Exe, $Arguments, $Working, $out, $err, $Seconds)
    $entry.process=$result
    Write-Json (Join-Path $ReportDirectory 'executions.json') $executions.ToArray()
    if (-not $result.AllOwnedProcessesExited) { throw "Owned job did not become empty: $Label" }
    if ($result.TimedOut) { throw "Owned command timeout: $Label" }
    if ($result.ExitCode -ne 0) { throw "Nonzero exit $($result.ExitCode): $Label" }
    $text = (Read-Log $out) + (Read-Log $err)
    if ($EngineLog) {
        if (-not (Test-Path -LiteralPath $EngineLog -PathType Leaf)) { throw "Missing actual engine log: $Label" }
        $text += Read-Log $EngineLog
    }
    $text = [regex]::Replace($text, '\x1b\[[0-?]*[ -/]*[@-~]', '')
    $engineError = [regex]::IsMatch($text, '(?m)^\s*(?:SCRIPT ERROR|ERROR):')
    $entry.engine_error_logged=$engineError
    Write-Json (Join-Path $ReportDirectory 'executions.json') $executions.ToArray()
    if ($engineError) { throw "Engine/script error in output or log: $Label" }
    return $entry
}

$sourceGuard = Join-Path $ownedRoot 'source_guard.py'
[IO.File]::WriteAllText($sourceGuard, @'
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve(); expected=sys.argv[2]; report=Path(sys.argv[3])
def git(*args): return subprocess.check_output(["git",*args],cwd=root)
assert git("rev-parse","HEAD").decode().strip()==expected,"source commit changed"
files={}
for row in git("ls-tree","-rz","HEAD").split(b"\0"):
 if not row: continue
 meta,name=row.split(b"\t",1); mode,kind,oid=meta.decode().split(); name=name.decode()
 assert mode in ("100644","100755") and kind=="blob","linked/submodule source refused"
 p=root/name
 assert p.resolve().is_relative_to(root) and p.is_file() and not p.is_symlink(),"unsafe source path"
 data=p.read_bytes()
 assert hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()==oid,"source Git blob mismatch: "+name
 files[name]={"mode":mode,"sha256":hashlib.sha256(data).hexdigest()}
generated={}
for raw in git("ls-files","--others","-z").split(b"\0"):
 if not raw: continue
 name=raw.decode(); p=root/name
 assert name.startswith(".godot/") or (name.endswith(".import") and name[:-7] in files) or (name.endswith(".uid") and name[:-4] in files),"unknown generated source: "+name
 assert p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root),"unsafe generated source"
 generated[name]=hashlib.sha256(p.read_bytes()).hexdigest()
report.write_text(json.dumps({"source_sha":expected,"files":files,"generated_metadata":generated},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Verified",len(files),"Git blobs;",len(generated),"generated metadata files")
'@, $utf8)

$summary = [ordered]@{schema_version=1; fixture_only=[bool]$SelfTest; windows_source_verified=$false; status='failed'; errors=@(); owned_root=$ownedRoot}
try {
    $python = (Get-Command python -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Owned $python @('--version') $checkout 20 'python-version'
    $summary.python = (Read-Log (Join-Path $ReportDirectory 'python-version-stdout.log')).Trim()
    $summary.os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    $summary.powershell = $PSVersionTable.PSVersion.ToString()
    if ($SelfTest) {
        $fixture = Join-Path $ownedRoot 'untrusted.zip'
        [IO.File]::WriteAllBytes($fixture, [byte[]](1,2,3))
        $rejected = $false
        try { Assert-Archive $fixture 3 ('0' * 64) } catch { if ($_.Exception.Message -notmatch 'SHA256 mismatch') { throw }; $rejected=$true }
        if (-not $rejected) { throw 'Wrong-hash fixture accepted.' }
        $git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $fixtureRepo = Join-Path $ownedRoot 'fixture Git'
        $null = Invoke-Owned $git @('init','--quiet',$fixtureRepo) $ownedRoot 20 'fixture-git-init'
        [IO.File]::WriteAllText((Join-Path $fixtureRepo 'fixture.txt'), 'original fixture', $utf8)
        $null = Invoke-Owned $git @('-C',$fixtureRepo,'add','fixture.txt') $ownedRoot 20 'fixture-git-add'
        $null = Invoke-Owned $git @('-C',$fixtureRepo,'-c','user.name=W01 fixture','-c','user.email=w01@fixture.invalid','commit','--quiet','-m','fixture') $ownedRoot 20 'fixture-git-commit'
        $null = Invoke-Owned $git @('-C',$fixtureRepo,'rev-parse','HEAD') $ownedRoot 20 'fixture-git-sha'
        $fixtureSha = (Read-Log (Join-Path $ReportDirectory 'fixture-git-sha-stdout.log')).Trim()
        $null = Invoke-Owned $python @($sourceGuard,$fixtureRepo,$fixtureSha,(Join-Path $ownedRoot 'fixture-source.json')) $ownedRoot 20 'fixture-source-ok'
        [IO.File]::WriteAllText((Join-Path $fixtureRepo 'fixture.txt'), 'changed fixture', $utf8)
        $rejected=$false
        try { $null = Invoke-Owned $python @($sourceGuard,$fixtureRepo,$fixtureSha,(Join-Path $ownedRoot 'fixture-source-invalid.json')) $ownedRoot 20 'fixture-source-changed' }
        catch { if ($_.Exception.Message -notmatch 'Nonzero exit') { throw }; $rejected=$true }
        if (-not $rejected) { throw 'Changed Git blob fixture accepted.' }
        $fake = Join-Path $ownedRoot 'fixture import.ps1'
        [IO.File]::WriteAllText($fake, @'
param($Channel,$Log)
[IO.File]::WriteAllText($Log,'fixture engine log')
if($Channel -eq 'stdout') { [Console]::Out.WriteLine('SCRIPT ERROR: fixture exit zero') }
if($Channel -eq 'stderr') { [Console]::Error.WriteLine('ERROR: fixture exit zero') }
if($Channel -eq 'log') { [IO.File]::WriteAllText($Log,'ERROR: fixture exit zero') }
exit 0
'@, $utf8)
        $pwsh = (Get-Process -Id $PID).Path
        $log = Join-Path $ReportDirectory 'fixture-ok-engine.log'
        $null = Invoke-Owned $pwsh @('-NoProfile','-NonInteractive','-File',$fake,'ok',$log) $ownedRoot 20 'fixture-ok' $log
        foreach ($channel in @('stdout','stderr','log')) {
            $log = Join-Path $ReportDirectory ('fixture-' + $channel + '-engine.log')
            $rejected = $false
            try { $null = Invoke-Owned $pwsh @('-NoProfile','-NonInteractive','-File',$fake,$channel,$log) $ownedRoot 20 ('fixture-' + $channel) $log }
            catch { if ($_.Exception.Message -notmatch 'Engine/script error') { throw }; $rejected=$true }
            if (-not $rejected) { throw "Exit-zero error fixture accepted: $channel" }
        }
        $parent = Join-Path $ownedRoot 'fixture child.ps1'
        [IO.File]::WriteAllText($parent, @'
$exe=(Get-Process -Id $PID).Path
Start-Process -NoNewWindow -FilePath $exe -ArgumentList @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 60')
exit 0
'@, $utf8)
        $rejected=$false
        try { $null=Invoke-Owned $pwsh @('-NoProfile','-NonInteractive','-File',$parent) $ownedRoot 5 'fixture-owned-child' }
        catch { if ($_.Exception.Message -notmatch 'Owned command timeout') { throw }; $rejected=$true }
        if (-not $rejected) { throw 'Child-process timeout fixture accepted.' }
        $childResult=$executions[$executions.Count-1].process
        if ($childResult.ExitCode -ne 0 -or $childResult.ObservedPids.Count -lt 2) { throw 'Fixture did not observe a normally exited parent and its remaining child.' }
        $summary.fixture_cases = @('wrong archive hash refused','changed Git blob refused','clean exit-zero import accepted','stdout/stderr/engine-log exit-zero errors refused','closed-parent owned child terminated and job empty')
        $summary.status='passed; fixtures only, no game or Windows source acceptance'
    } else {
        if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Actual download/source validation is restricted to this GitHub runner invocation.' }
        if ($summary.python -ne 'Python 3.14.6') { throw "Pinned Python 3.14.6 required: $($summary.python)" }
        $git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $sha = (& $git -C $checkout rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve immutable source SHA.' }
        $source = Join-Path $ownedRoot '源码 source with spaces'
        $null = Invoke-Owned $git @('clone','--local','--no-hardlinks','--no-checkout',$checkout,$source) $checkout 60 'clone'
        $null = Invoke-Owned $git @('-c','core.autocrlf=false','-C',$source,'checkout','--detach',$sha) $checkout 60 'checkout'
        $summary.source_sha=$sha
        $summary.candidate_head_sha=$env:W01_CANDIDATE_HEAD
        $null = Invoke-Owned $python @($sourceGuard,$source,$sha,(Join-Path $ReportDirectory 'source-before.json')) $source 60 'source-before'
        if (Test-Path -LiteralPath (Join-Path $source '.godot')) { throw 'Cold source unexpectedly has an import cache.' }
        $zip = Join-Path $ownedRoot 'Godot.zip'
        $url = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
        Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 180
        $zipHash='731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
        Assert-Archive $zip 86013866 $zipHash
        $summary.archive=@{url=$url; size=86013866; sha256=$zipHash}
        $engineDir = Join-Path $ownedRoot 'engine'
        Expand-Archive -LiteralPath $zip -DestinationPath $engineDir
        $engine = Join-Path $engineDir 'Godot_v4.7.2-stable_win64_console.exe'
        if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Pinned archive lacks its Windows console editor.' }
        $summary.engine_files=@{}
        Get-ChildItem -LiteralPath $engineDir -File -Recurse | ForEach-Object { $summary.engine_files[$_.FullName.Substring($engineDir.Length+1)]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        $null = Invoke-Owned $engine @('--version') $source 20 'engine-version'
        $version=(Read-Log (Join-Path $ReportDirectory 'engine-version-stdout.log')).Trim()
        if ($version -notmatch '^4\.7\.2(?:\.|$)') { throw "Wrong effective engine version: $version" }
        $summary.engine_version=$version
        $summary.cold_cache_initially_absent=$true
        $importLog=Join-Path $ReportDirectory 'import-engine.log'
        $null = Invoke-Owned $engine @('--headless','--path',$source,'--import','--log-file',$importLog) $source 120 'import' $importLog
        $summary.imported_texture_count=@(Get-ChildItem -LiteralPath (Join-Path $source '.godot/imported') -File -Filter '*.ctex').Count
        if ($summary.imported_texture_count -lt 1) { throw 'Cold import did not produce actual texture resources.' }
        # P07 owns the probe/provider. Missing dependency is a real failure; never skip.
        $fontOutput=Join-Path $tempBase 'w01-font'
        if (Test-Path -LiteralPath $fontOutput) { throw 'Font probe output must be fresh.' }
        $fontLog=Join-Path $ReportDirectory 'font-engine.log'
        $null = Invoke-Owned $engine @('--headless','--path',$source,'--log-file',$fontLog,'--script','game/ui/checks/portable_font.gd','--',$fontOutput) $source 120 'portable-font' $fontLog
        $font=Read-Log (Join-Path $fontOutput 'font-report.json') | ConvertFrom-Json -AsHashtable
        if ($font.protocol -ne 1 -or $font.checks -lt 1 -or @($font.failures).Count -or @($font.missing).Count -or -not @($font.fonts).Count -or -not @($font.bindings).Count -or $font.required_han -lt 1 -or $font.layouts.Count -ne 4) { throw 'Font probe has missing glyphs/bindings or incomplete evidence.' }
        $manifest=Read-Log (Join-Path $source 'assets/fonts/font-manifest.json') | ConvertFrom-Json -AsHashtable
        $expectedFonts=@{}
        foreach ($row in @($manifest.primary)+@($manifest.fallbacks)) { $expectedFonts[$row.path]=$row.sha256 }
        foreach ($row in $font.fonts) {
            if ($row.class -ne 'FontFile' -or $row.allow_system_fallback -ne $false -or -not $expectedFonts.Contains($row.path) -or $row.sha256 -ne $expectedFonts[$row.path]) { throw 'Font probe data differs from pinned packaged font.' }
        }
        foreach ($row in $font.bindings) {
            if (-not @($font.fonts | Where-Object { $_.path -eq $row.font_path -and $_.instance -eq $row.font_instance }).Count) { throw 'Main text binding does not use the actual packaged font instance.' }
        }
        $before=Read-Log (Join-Path $ReportDirectory 'source-before.json') | ConvertFrom-Json -AsHashtable
        foreach ($name in @('game/ui/portable_font.gd','game/ui/main.gd','game/ui/checks/portable_font.gd','assets/fonts/font-manifest.json','assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf.import')) {
            if ($font.source_sha256[$name] -ne $before.files[$name].sha256) { throw "Font probe source differs from verified Git blob: $name" }
        }
        $summary.portable_font=@{checks=$font.checks; required_characters=$font.required_characters; required_han=$font.required_han; bindings=$font.bindings.Count; fonts=$font.fonts; missing=$font.missing; source_sha256=$font.source_sha256; native_pixels_verified=$false}
        $gateReport=Join-Path $ReportDirectory 'gate-report.json'
        try {
            $null = Invoke-Owned $python @((Join-Path $source 'tools/gate.py'),'--stage','prototype','--godot',$engine,'--report',$gateReport) $source $GateTimeoutSeconds 'gate'
        } catch {
            $gateFailure=$_
            # gate.py discards TimeoutExpired output. Preserve the original failure;
            # a bounded rerun adds diagnostics only, never replacement acceptance.
            if (Test-Path -LiteralPath $gateReport -PathType Leaf) {
                $failedGate=Read-Log $gateReport | ConvertFrom-Json -AsHashtable
                if (($failedGate.errors -join "`n") -match 'command timed out after 120s:.*quality-slice') {
                    $summary.quality_timeout_diagnostic=@{acceptance=$false; original_gate_status=$failedGate.status; selected_case='Q02'}
                    $diagnosticLog=Join-Path $ReportDirectory 'quality-diagnostic-engine.log'
                    try {
                        $null = Invoke-Owned $engine @('--headless','--path',$source,'--log-file',$diagnosticLog,'--script','tests/run.gd','--','--suite','quality-slice','--case','Q02','--report',(Join-Path $ReportDirectory 'quality-diagnostic-cases.json')) $source 120 'quality-diagnostic' $diagnosticLog
                        $summary.quality_timeout_diagnostic.result='completed; original gate still failed'
                    } catch {
                        $summary.quality_timeout_diagnostic.result=$_.Exception.Message
                    }
                }
            }
            throw $gateFailure
        }
        $gate=Get-Content -LiteralPath $gateReport -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        if ($gate.status -ne 'passed' -or $gate.gate -ne 'prototype' -or $gate.candidate.sha -ne $sha) { throw 'Actual source gate did not pass for this source SHA.' }
        if ((($gate.case_reports.Keys | Sort-Object) -join ',') -ne 'prototype,quality-slice') { throw 'Both actual suites must be present.' }
        $summary.case_reports=@{}
        foreach ($suite in @('prototype','quality-slice')) {
            $rows=$gate.case_reports[$suite].cases
            if (-not $rows -or @($rows | Where-Object { $_.status -ne 'passed' -or $_.checks -lt 1 }).Count) { throw "Failed/empty/skipped real cases: $suite" }
            $summary.case_reports[$suite]=@{cases=$rows.Count; checks=($rows | Measure-Object -Property checks -Sum).Sum}
        }
        $null = Invoke-Owned $python @($sourceGuard,$source,$sha,(Join-Path $ReportDirectory 'source-after.json')) $source 60 'source-after'
        foreach ($name in $summary.engine_files.Keys) {
            if ((Get-FileHash -LiteralPath (Join-Path $engineDir $name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $summary.engine_files[$name]) { throw "Engine changed during execution: $name" }
        }
        $summary.windows_source_verified=$true
        $summary.status='passed; Windows source editor only'
        $summary.limitations=@('No exported EXE/PCK or native Windows game package','No rendered UI, physical controller/touch or QH evidence','No Steam upload/publication')
    }
} catch {
    $summary.errors=@($_.Exception.Message)
    [Console]::Error.WriteLine($_.Exception.ToString())
} finally {
    $summary.executions=$executions.ToArray()
    Write-Json (Join-Path $ReportDirectory 'summary.json') $summary
    # No deletion: retain this invocation's source, ZIP and diagnostics in runner temp.
    # The workflow uploads only explicit reports/logs, never these source/engine/save trees.
}
if ($summary.status -notlike 'passed*') { exit 1 }
exit 0
