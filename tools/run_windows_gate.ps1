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

# CREATE_SUSPENDED closes the spawn-before-job-assignment race. The unnamed job
# never allows breakaway; closing it also kills this invocation's descendants.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public sealed class W01Result {
 public int ParentPid, ExitCode; public bool TimedOut, AllOwnedProcessesExited;
 public long ElapsedMilliseconds; public int[] ObservedPids;
}
public static class W01Process {
 [StructLayout(LayoutKind.Sequential)] struct BasicLimit {
  public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max;
  public uint ActiveLimit; public UIntPtr Affinity; public uint Priority, Scheduling;
 }
 [StructLayout(LayoutKind.Sequential)] struct Io {
  public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
 }
 [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {
  public BasicLimit Basic; public Io Io;
  public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
 }
 [StructLayout(LayoutKind.Sequential)] struct Accounting {
  public long User, Kernel, PeriodUser, PeriodKernel;
  public uint Faults, Total, Active, Terminated;
 }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
  public uint Size; public string Reserved, Desktop, Title;
  public uint X,Y,Width,Height,CharsX,CharsY,Fill,Flags;
  public ushort Show, ReservedSize; public IntPtr ReservedData, Input, Output, Error;
 }
 [StructLayout(LayoutKind.Sequential)] struct ProcessInfo {
  public IntPtr Process, Thread; public uint Pid, Tid;
 }
 [StructLayout(LayoutKind.Sequential)] struct Security {
  public uint Size; public IntPtr Descriptor; public int Inherit;
 }
 [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
 static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string name,uint access,uint share,ref Security security,uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a, string name);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j,int c,ref ExtendedLimit v,uint n);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr j,int c,IntPtr v,uint n,IntPtr used);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j,IntPtr p);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr j,uint code);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr p,uint code);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
 [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
 static extern bool CreateProcessW(string app,StringBuilder cmd,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref Startup si,out ProcessInfo pi);
 [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr t);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr p,out uint code);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 static void Check(bool ok,string operation="Win32 operation") {
  if(!ok) { int code=Marshal.GetLastWin32Error(); throw new Win32Exception(code,operation+": "+new Win32Exception(code).Message); }
 }
 static uint Active(IntPtr job) {
  int size=Marshal.SizeOf<Accounting>(); IntPtr p=Marshal.AllocHGlobal(size);
  try { Check(QueryInformationJobObject(job,1,p,(uint)size,IntPtr.Zero)); return Marshal.PtrToStructure<Accounting>(p).Active; }
  finally { Marshal.FreeHGlobal(p); }
 }
 static void Observe(IntPtr job,HashSet<int> ids) {
  int size=8+IntPtr.Size*4096; IntPtr p=Marshal.AllocHGlobal(size);
  try {
   Check(QueryInformationJobObject(job,3,p,(uint)size,IntPtr.Zero));
   int count=Marshal.ReadInt32(p,4); if(count<0 || count>4096) throw new Exception("Owned job PID list overflow");
   for(int i=0;i<count;i++) ids.Add((int)Marshal.ReadIntPtr(p,8+i*IntPtr.Size).ToInt64());
  } finally { Marshal.FreeHGlobal(p); }
 }
 // CommandLineToArgvW-compatible quoting, including spaces, quotes and trailing slashes.
 static string Quote(string arg) {
  var b=new StringBuilder("\""); int slashes=0;
  foreach(char c in arg) {
   if(c=='\\') { slashes++; continue; }
   if(c=='"') { b.Append('\\',slashes*2+1); b.Append(c); }
   else { b.Append('\\',slashes); b.Append(c); }
   slashes=0;
  }
  b.Append('\\',slashes*2); b.Append('"'); return b.ToString();
 }
 public static W01Result Run(string exe,string[] args,string cwd,string stdout,string stderr,int seconds) {
  IntPtr job=CreateJobObject(IntPtr.Zero,null); Check(job!=IntPtr.Zero);
  ProcessInfo pi=new ProcessInfo(); var ids=new HashSet<int>(); var watch=Stopwatch.StartNew();
  try {
   var limits=new ExtendedLimit(); limits.Basic.Flags=0x2000;
   Check(SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf<ExtendedLimit>()),"configure owned job");
   var security=new Security(); security.Size=(uint)Marshal.SizeOf<Security>(); security.Inherit=1;
   using(var output=new FileStream(stdout,FileMode.CreateNew,FileAccess.Write,FileShare.ReadWrite))
   using(var error=new FileStream(stderr,FileMode.CreateNew,FileAccess.Write,FileShare.ReadWrite))
   using(var input=CreateFileW("NUL",0x80000000,3,ref security,3,0,IntPtr.Zero)) {
    Check(!input.IsInvalid,"open NUL stdin");
    IntPtr oh=output.SafeFileHandle.DangerousGetHandle(), eh=error.SafeFileHandle.DangerousGetHandle(), ih=input.DangerousGetHandle();
    Check(SetHandleInformation(oh,1,1)); Check(SetHandleInformation(eh,1,1)); Check(SetHandleInformation(ih,1,1));
    var si=new Startup(); si.Size=(uint)Marshal.SizeOf<Startup>(); si.Flags=0x100;
    si.Input=ih; si.Output=oh; si.Error=eh;
    var command=new StringBuilder(Quote(exe)); foreach(var arg in args) command.Append(" ").Append(Quote(arg));
    Check(CreateProcessW(exe,command,IntPtr.Zero,IntPtr.Zero,true,0x08000004,IntPtr.Zero,cwd,ref si,out pi),
     "CreateProcess exe="+exe+" cwd="+cwd+" command="+command);
    // If assignment fails, only the still-suspended process we just created is terminated.
    if(!AssignProcessToJobObject(job,pi.Process)) {
     int code=Marshal.GetLastWin32Error(); TerminateProcess(pi.Process,125); throw new Win32Exception(code);
    }
    Check(SetHandleInformation(oh,1,0)); Check(SetHandleInformation(eh,1,0)); Check(SetHandleInformation(ih,1,0));
    ids.Add((int)pi.Pid); Check(ResumeThread(pi.Thread)!=0xffffffff);
    bool timedOut=false;
    while(Active(job)>0) {
     Observe(job,ids);
     if(watch.Elapsed.TotalSeconds>=seconds) { timedOut=true; Check(TerminateJobObject(job,124)); break; }
     System.Threading.Thread.Sleep(25);
    }
    var cleanup=Stopwatch.StartNew();
    while(Active(job)>0 && cleanup.Elapsed.TotalSeconds<5) System.Threading.Thread.Sleep(25);
    uint exit; Check(GetExitCodeProcess(pi.Process,out exit));
    return new W01Result { ParentPid=(int)pi.Pid,ExitCode=unchecked((int)exit),TimedOut=timedOut,
     AllOwnedProcessesExited=Active(job)==0,ObservedPids=new List<int>(ids).ToArray(),ElapsedMilliseconds=watch.ElapsedMilliseconds };
   }
  } finally {
   if(pi.Thread!=IntPtr.Zero) CloseHandle(pi.Thread);
   if(pi.Process!=IntPtr.Zero) CloseHandle(pi.Process);
   CloseHandle(job);
  }
 }
}
'@

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
        # Run the unchanged P07 producer at both declared headless viewport sizes.
        $fontRuns=@{}
        $before=Read-Log (Join-Path $ReportDirectory 'source-before.json') | ConvertFrom-Json -AsHashtable
        foreach ($sizeCase in @(@{name='large';leaf='w01-font';width=1440;height=904},@{name='small';leaf='w01-font-small';width=844;height=390})) {
            $fontOutput=Join-Path $tempBase $sizeCase.leaf
            if (Test-Path -LiteralPath $fontOutput) { throw 'Font probe output must be fresh.' }
            $fontLog=Join-Path $ReportDirectory $(if ($sizeCase.name -eq 'large') { 'font-engine.log' } else { 'font-small-engine.log' })
            $fontArgs=@('--headless','--path',$source,'--log-file',$fontLog,'--script','game/ui/checks/portable_font.gd','--',$fontOutput,'--path-tests')
            if ($sizeCase.name -eq 'small') { $fontArgs+=@('--small') }
            $null = Invoke-Owned $engine $fontArgs $source 120 ('portable-font-'+$sizeCase.name) $fontLog
            $font=Read-Log (Join-Path $fontOutput 'font-report.json') | ConvertFrom-Json -AsHashtable
            if ($font.protocol -ne 1 -or $font.checks -lt 1 -or @($font.failures).Count -or @($font.missing).Count -or -not @($font.fonts).Count -or -not @($font.bindings).Count -or $font.required_han -lt 1 -or $font.layouts.Count -ne 4 -or $font.output_policy.fresh -ne $true) { throw 'Font probe has missing glyphs/bindings or incomplete fresh evidence.' }
            if ($font.output_directory.Replace('\','/') -cne $fontOutput.Replace('\','/')) { throw 'Font probe used the wrong output directory.' }
            if ((($font.layouts.entry | Sort-Object) -join ',') -cne 'ledger,menu-board,recipe-book,vendor') { throw 'World font probe did not check all four production books.' }
            foreach ($layout in $font.layouts) {
                $dimensions=[regex]::Match($layout.ui_size,'^\(\s*(\d+)(?:\.0+)?,\s*(\d+)(?:\.0+)?\)$')
                if (-not $dimensions.Success -or [int]$dimensions.Groups[1].Value -ne $sizeCase.width -or [int]$dimensions.Groups[2].Value -ne $sizeCase.height) { throw 'Font probe viewport dimensions differ from the declared size.' }
            }
            $manifest=Read-Log (Join-Path $source 'assets/fonts/font-manifest.json') | ConvertFrom-Json -AsHashtable
            $expectedFonts=@{}
            foreach ($row in @($manifest.primary)+@($manifest.fallbacks)) { $expectedFonts[$row.path]=$row.sha256 }
            foreach ($row in $font.fonts) {
                if ($row.class -ne 'FontFile' -or $row.allow_system_fallback -ne $false -or -not $expectedFonts.Contains($row.path) -or $row.sha256 -ne $expectedFonts[$row.path]) { throw 'Font probe data differs from pinned packaged font.' }
            }
            foreach ($row in $font.bindings) {
                if (-not @($font.fonts | Where-Object { $_.path -eq $row.font_path -and $_.instance -eq $row.font_instance }).Count) { throw 'Main text binding does not use the actual packaged font instance.' }
            }
            foreach ($name in @('game/ui/portable_font.gd','game/ui/main.gd','game/ui/checks/portable_font.gd','assets/fonts/font-manifest.json','assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf.import','game/ui/world_play.gd','game/ui/world/world_input.gd','game/ui/world/world_books.gd','game/ui/world/world_controller.gd')) {
                if ($font.source_sha256[$name] -ne $before.files[$name].sha256) { throw "Font probe source differs from verified Git blob: $name" }
            }
            $fontRuns[$sizeCase.name]=@{checks=$font.checks; required_characters=$font.required_characters; required_han=$font.required_han; bindings=$font.bindings.Count; fonts=$font.fonts; missing=$font.missing; layouts=$font.layouts; path_cases=$font.path_cases; source_sha256=$font.source_sha256; native_pixels_verified=$false}
        }
        $summary.portable_font=$fontRuns.large
        $summary.portable_font_small=$fontRuns.small

        # Reuse the fixture-free H07 Main probe in a separate bound source input.
        # This creates no app, engine copy, export or native window.
        $mainHelper=Join-Path $ownedRoot 'source_main_checks.py'
        [IO.File]::WriteAllText($mainHelper, @'
import json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[2])/'tools'))
import build_local_demo as demo
command,source,binding_path=sys.argv[1:4]
if command=='prepare':
 project,profile,probe,sha=sys.argv[4:]
 binding=demo.prepare_source_probe(Path(source),sha,Path(project),profile,Path(probe))
 demo.validate_source_probe_projection(binding);demo.json_write(Path(binding_path),binding)
else:
 binding=demo.json_read(Path(binding_path));mode,report_path,execution_path,label,engine_dir=sys.argv[4:]
 report=demo.json_read(Path(report_path));rows=json.loads(Path(execution_path).read_text(encoding='utf-8-sig'))
 entry=next(row for row in rows if row['label']==label);process=entry['process']
 demo.require(process['ExitCode']==0 and process['AllOwnedProcessesExited'] and not process['TimedOut'],'Main process did not finish cleanly')
 demo.require(report['process_id'] in process['ObservedPids'],'Main PID was not observed in the owned Job')
 executable=Path(report['executable']).resolve();engine=Path(engine_dir).resolve()
 demo.require(executable in [engine/'Godot_v4.7.2-stable_win64.exe',engine/'Godot_v4.7.2-stable_win64_console.exe'],'Main used an unknown engine')
 demo.validate_probe(report,{'pid':report['process_id']},mode,binding['profile'],binding['source_commit'],executable,binding['main_scene'],binding['source_files_sha256'])
 expected=Path(os.environ['APPDATA'])/binding['profile']
 demo.require(str(Path(report['user_data_dir']).resolve())==str(expected.resolve()),'unexpected Windows userdata root')
 demo.validate_source_probe_projection(binding)
 if mode=='restore':
  save=demo.json_read(Path(report_path).with_name('main-save.json'));player=demo.json_read(Path(report_path).with_name('main-player-directory.json'))
  demo.require(len({player['process_id'],save['process_id'],report['process_id']})==3,'Main checks did not use three processes')
  demo.require(demo.same_snapshot(save['snapshot'],report['snapshot']) and all(save[k]==report[k] for k in ['save_hash','backup_hash']),'Main restore changed the snapshot or rewrote primary/backup')
 print('Verified source-only Main',mode,report['process_id'])
'@, $utf8)
        $mainSource=Join-Path $ownedRoot '默认档 source probe'
        $mainProbe=Join-Path $ownedRoot 'source-main-probe.gd'
        $mainBinding=Join-Path $ReportDirectory 'main-source-binding.json'
        $mainProfile='MoonlanternH07Source/'+[guid]::NewGuid().ToString('N')+'/verify'
        $null=Invoke-Owned $python @($mainHelper,'prepare',$source,$mainBinding,$mainSource,$mainProfile,$mainProbe,$sha) $source 60 'main-prepare'
        $mainImportLog=Join-Path $ReportDirectory 'main-import-engine.log'
        $null=Invoke-Owned $engine @('--headless','--path',$mainSource,'--import','--log-file',$mainImportLog) $mainSource 120 'main-import' $mainImportLog
        $previousMainEnvironment=@{}
        foreach ($key in @('MOON_DEMO_MODE','MOON_DEMO_REPORT','MOON_DEMO_EXPECTED_PROFILE','MOON_DEMO_BUILD_ID')) { $previousMainEnvironment[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
        try {
            $env:MOON_DEMO_EXPECTED_PROFILE=$mainProfile; $env:MOON_DEMO_BUILD_ID=$sha
            foreach ($mode in @('player-directory','save','restore')) {
                $env:MOON_DEMO_MODE=$mode
                $env:MOON_DEMO_REPORT=Join-Path $ReportDirectory ('main-'+$mode+'.json')
                $mainLog=Join-Path $ReportDirectory ('main-'+$mode+'-engine.log')
                $label='main-'+$mode
                $null=Invoke-Owned $engine @('--headless','--path',$mainSource,'--log-file',$mainLog,'--script',$mainProbe) $mainSource 120 $label $mainLog
                $null=Invoke-Owned $python @($mainHelper,'validate',$source,$mainBinding,$mode,$env:MOON_DEMO_REPORT,(Join-Path $ReportDirectory 'executions.json'),$label,$engineDir) $source 60 ($label+'-validate')
            }
        } finally {
            foreach ($key in $previousMainEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$previousMainEnvironment[$key],'Process') }
        }
        $summary.world_main_default=@{verified=$true; profile=$mainProfile; source_sha=$sha; independent_processes=3; fixture_free_source_input=$true; package_created=$false; native_verified=$false; input_route_verified=$false; binding_sha256=(Get-FileHash -LiteralPath $mainBinding -Algorithm SHA256).Hash.ToLowerInvariant()}
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
        if ((($gate.case_reports.Keys | Sort-Object) -join ',') -ne 'prototype,quality-slice,world-slice') { throw 'All three actual suites must be present.' }
        $summary.case_reports=@{}
        foreach ($suite in @('prototype','quality-slice','world-slice')) {
            $rows=$gate.case_reports[$suite].cases
            if (-not $rows -or @($rows | Where-Object { $_.status -ne 'passed' -or $_.checks -lt 1 }).Count) { throw "Failed/empty/skipped real cases: $suite" }
            if ($suite -eq 'world-slice' -and ((($rows.id | Sort-Object) -join ',') -cne 'WS01,WS02,WS03,WS04,WS05,WS06')) { throw 'World must execute exactly WS01-WS06; runtime/human are separate.' }
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
