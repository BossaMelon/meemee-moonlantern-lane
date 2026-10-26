#requires -Version 7.0
[CmdletBinding()]
param([string]$RequestPath, [string]$ResultPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows Job Objects require Windows.' }
# Shared W01 native boundary; caller cancellation closes its non-inheritable Job.
if (-not ('W01Process' -as [type])) {
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

}
if ($RequestPath -or $ResultPath) {
    if (-not $RequestPath -or -not $ResultPath) { throw 'Both request/result paths are required.' }
    $utf8=[Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding=$utf8
    function Assert-Canonical([string]$Path, [bool]$Exists) {
        if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw 'Absolute path required.' }
        $full=[IO.Path]::GetFullPath($Path)
        if ($full.Replace('\','/') -cne $Path.Replace('\','/')) { throw 'Noncanonical path.' }
        $cursor=$full
        while ($cursor) {
            if (Test-Path -LiteralPath $cursor) {
                if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked/reparse path refused.' }
            }
            $parent=[IO.Path]::GetDirectoryName($cursor)
            if ($parent -eq $cursor) { break }; $cursor=$parent
        }
        if ($Exists -and -not (Test-Path -LiteralPath $full)) { throw 'Input path missing.' }
        return $full
    }
    $null=Assert-Canonical $RequestPath $true
    $null=Assert-Canonical $ResultPath $false
    if (Test-Path -LiteralPath $ResultPath) { throw 'Result must be fresh.' }
    $raw=[IO.File]::ReadAllText($RequestPath,$utf8)
    $document=[Text.Json.JsonDocument]::Parse($raw)
    try {
        $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $document.RootElement.EnumerateObject()) {
            if (-not $keys.Add($property.Name)) { throw 'Duplicate request key.' }
        }
    } finally { $document.Dispose() }
    $request=ConvertFrom-Json -InputObject $raw -AsHashtable
    if ((($request.Keys | Sort-Object) -join ',') -cne 'argv,cwd,log_path,nonce,protocol,timeout_seconds') { throw 'Wrong request keys.' }
    if ($request.protocol -cne 'h06-owned-process-v1' -or $request.nonce -isnot [string] -or -not $request.nonce) { throw 'Wrong protocol/nonce.' }
    if ($request.argv -isnot [array] -or $request.argv.Count -lt 1 -or @($request.argv | Where-Object { $_ -isnot [string] -or -not $_ }).Count) { throw 'Invalid argv.' }
    if ($request.timeout_seconds -is [bool] -or $request.timeout_seconds -isnot [ValueType] -or $request.timeout_seconds -le 0 -or $request.timeout_seconds -gt 900) { throw 'Invalid timeout.' }
    $exe=Assert-Canonical $request.argv[0] $true
    $cwd=Assert-Canonical $request.cwd $true
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or -not (Test-Path -LiteralPath $cwd -PathType Container)) { throw 'Invalid executable/cwd.' }
    $log=Assert-Canonical $request.log_path $false
    if (Test-Path -LiteralPath $log) { throw 'Log must be fresh.' }
    $stderr=$log+'.stderr-local'
    $started=[long](([DateTime]::UtcNow.Ticks-[long]621355968000000000)*[long]100)
    $arguments=[string[]]@($request.argv | Select-Object -Skip 1)
    $result=[W01Process]::Run($exe,$arguments,$cwd,$log,$stderr,[int][Math]::Ceiling($request.timeout_seconds))
    # Preserve both native channels; their individual interleaving is not asserted.
    $errorText=[IO.File]::ReadAllText($stderr,$utf8)
    [IO.File]::AppendAllText($log,"`n"+$errorText,$utf8)
    $ended=[long](([DateTime]::UtcNow.Ticks-[long]621355968000000000)*[long]100)
    $signals=if ($result.TimedOut) { @('TerminateJobObject') } else { @() }
    $value=[ordered]@{protocol=$request.protocol;nonce=$request.nonce;argv=@($request.argv);cwd=$request.cwd;pid=$result.ParentPid;started_ns=$started;ended_ns=$ended;exit_code=$result.ExitCode;timed_out=$result.TimedOut;interrupted=$false;ownership='windows_job';owned_empty=$result.AllOwnedProcessesExited;cleanup_signals=@($signals);log_sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLowerInvariant()}
    $bytes=$utf8.GetBytes((ConvertTo-Json -InputObject $value -Depth 20))
    $stream=[IO.File]::Open($ResultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    exit 0
}
