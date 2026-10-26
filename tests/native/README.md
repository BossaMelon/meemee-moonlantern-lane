# H06 native harness handoff

H06 owns only the eight registered files in this directory. This is a finite
paired-release harness, not product functionality or an export builder. Task and
current delivery status remain in `harness/tasks.json` and `docs/project-status.md`.

H06 fixture/schema/controlled-child acceptance establishes **harness-ready**. It
cannot establish release compilation, native gameplay, pixels, Windows execution,
physical input, QH, a full night, human play quality or deployment. D02 consumes a
root-accepted immutable H06 candidate, then P08 runs its actual package pair.
Product, QA/harness and builder revisions are independently bound; the product
freeze must contain P09. A combined independent review is coordinated by root.

## Entrypoints and authority

From the repository root:

```sh
python3 tests/native/test_native_harness.py --report /absolute/new-evidence/fixture-report.json
python3 tests/native/run_native.py validate --kind BuildManifest --input /absolute/manifest.json
python3 tests/native/run_native.py native --manifest /absolute/manifest.json --profile release_headless --output /absolute/new-run
python3 tools/with_render_lock.py -- python3 tests/native/run_native.py native --manifest /absolute/manifest.json --profile mac_release_rendered --output /absolute/new-rendered-run
```

`validate` checks a document's protocol shape only and prints that limitation.
`native` requires actual files, frozen source identities, an unused namespace and
supported process ownership; missing packages/templates/Windows helper fail
nonzero. It never promotes a fixture summary into native evidence. Output must be
a new canonical directory whose parent exists. Paths with traversal, symlinks or
Windows junctions are rejected. Windows drive paths accept `/` or `\` separators;
no casefold is used to equate different names. Runtime user/save/executable paths
also require actual filesystem identity and matching parent/name. The literal
`user://profiles/rain-night-v1/moonlantern.json` is unchanged.

A native invocation consumes the namespace, even if it fails. Preserve it and its
evidence. D02 supplies a new pair/new namespaces for another independent run;
never delete saves or source to manufacture a fresh/restore result. The restore
process alone intentionally reuses the first process's verification namespace.

## Frozen four-document protocol

`protocol.schema.json` defines **BuildManifest**, **RunRequest**,
**ProcessObservation**, **NativeResult**. Supporting `$defs` are shapes inside
those four documents, not further workflow phases. The stdlib validator accepts
only the JSON-Schema vocabulary these definitions use. It rejects duplicate JSON
keys and nonfinite numbers; the source comparator covers all snapshot fields,
including extra/missing keys and array order, and distinguishes boolean from
number. JSON `1` and `1.0` may represent the same saved numeric value.

**BuildManifest** is created by D02 and read again against actual files by H06:

- `source_commit`/`source_tree`: product snapshot. `source_files` maps `res://`
  source paths to byte lengths and SHA256; include project.godot, every direct
  production payload and every source of an import. Every supplied source hash is
  checked against this exact Git revision, not the caller's mutable checkout.
- `builder_revision`/`builder_source_sha256`: actual
  `tools/build_native_demo.py`. The actual file must match its recorded hash and
  revision. The audit script and Windows Job helper also match that revision.
- `harness.commit`, contract/schema/QA/runner SHA256: actual H06 candidate. The QA
  UID and reused pure-comparison/owned-group helpers are revision checked too.
- Exact Godot `4.7.2.stable.official.ed1daf0bf`, editor file and the task-local
  official TPZ: 1,281,349,702 bytes, SHA256
  `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.
  The pin is a contract constant, not an optional manifest trust label. No
  downloader/global installer is part of H06. `template_member_chain` has one
  Windows member or two Mac members through `macos.zip`; the leaf is the matching
  `windows_release_<arch>.exe` or `godot_macos_release.universal`, never debug.
  Each unique member is bounded to 512 MiB. `template_member_sha256` is the final
  executable's hash, never the enclosing ZIP's hash. The host reads that exact
  archive chain and compares both final executables byte-for-byte with the leaf.
  `transformations` is fixed to `[]`: resource editing, signing or other binary
  transformations require a later explicit decision based on D02 evidence. D02
  supplies actual full member paths from the real TPZ; unknown layout fails closed.
- Fixed policy: script text mode 0; staging-only
  `editor/export/convert_text_resources_to_binary=false`; external PCK. This is
  not a runtime toggle and does not change source scenes/UIDs. Same-Mac fresh PCK
  reproducibility research is not cross-OS or actual release execution proof.
- Each package supplies root, executable/PCK/optional external override file,
  namespace, OS userdir, actual inventory and import targets. Namespace shape is
  `MeeMeeMoonlanternLane-H06/<32 lowercase hex>/<player|verification>`.
- `setting_hashes` and `setting_values` describe every actual `project.binary`
  entry; `effective_setting_values` includes the narrowly permitted external
  override. `staging_delta` records source literals and effective values only for
  the fixed export policy, namespace and verification QA autoload. Unknown keys
  or values differing from source/policy fail; defaults elided by Godot need not
  appear as serialized entries. Source settings use the finite scalar/string
  array types already in this product; new variants need an explicit change.
- `guards` lists existing old-save/old-package files (including expected absence)
  to compare before/after. Include the relevant old saves and r2 recovery package;
  the harness never writes them. Raw primary/backup data are not upload outputs.

The host reads the actual standalone, unencrypted, non-sparse Godot 4.7.2 PCK v4
container, checks entry ranges/MD5, hashes every payload and compares the complete
inventory. Unknown formats/flags fail. This version-pinned reader follows the
[engine's file-format implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/file_access_pack.cpp),
not a promise of a stable public PCK parsing API. Exported ConfigFile `.import`
metadata may contain multiline Variants; only explicit remap path keys are parsed
and all target payloads must exist. D02 still performs its Godot resource audit.

Player cannot contain tests/UI checks/QA. Verification may add only the declared
QA `.gd`/optional `.uid`. `project.binary` is compared by raw per-key Variant
bytes; only the named isolation/autoload changes are permitted. UID cache maps
must preserve every production UID/path and may add only a fixed QA resource.
Other changed production payload bytes fail. Required attribution files, font
manifest, OFL/NOTICE are explicit contract entries. Real Main font data, fallback
settings and visible text bindings are observed without calling a provider that
could repair them. Neither `.godot` nor `project.binary` is blanket-exempt.

**RunRequest** is generated by the host; no arbitrary commands/state/seed/scene
or save-path override is accepted. The release command uses normal export layout:

```text
<actual release executable> <fixed supported engine options> -- --p08-request <absolute request JSON>
```

No `--script`, `--main-pack`, `--path` or invented `--user-data-dir` is used on the
release template. Public support and actual binary capability are separate:
version/help are captured from the actual executable, then player is smoked with
`--headless --quit-after 12`. This proves bounded process startup, not player
Main-ready/UI/save behavior. Movie writing is not part of this v1 runner.
[Godot 4.7 CLI](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html),
[ProjectSettings overrides](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html).

**ProcessObservation** is emitted only by the verification Node autoload. It
subscribes before Main arrives, observes `ready`, then checks the actual
`current_scene` and script identity. No Main instance/scene replacement is made.
It reads the default path and complete product snapshots, injects real pointer
motion/down/up through `Input.parse_input_event`, and records actual controls and
viewport-to-window transforms. Sequence:

```text
world_lane → world_stall → batch_1 → buy_flour → sheet_close → pause → save → quit
```

One successful buy must produce 60→58 cash and 0→1 flour plus the actual
UID/ledger/request change. Pause/save are real controls. The first process's
pre-quit complete snapshot must match the actual primary after host-confirmed
exit. The second independent process must compare its complete startup and
settled state, with zero injected input, against that snapshot and each file's
own previous raw hash. A historical backup may differ from primary. Only after
that barrier does it click the restored pause menu's quit button. A subsequent
legal backup rotation is recorded separately from automatic restore.

**NativeResult** belongs to the host. A child may report quit intent, never that
its process has actually exited. Successful cases require actual exit 0, no
engine parse/error diagnostics, no timeout/interruption, no cleanup signals and
no owned residual descendants. Missing/duplicate/unknown/skipped/zero-check cases
or a summary without raw evidence fail. `checks: 1` means the case's compound
predicate was evaluated; it is not an assertion-count claim. Fixture results are
separate and can only produce `harness-ready`, never a native `passed` outcome.

## Fixed cases and process ownership

Both profiles require: `P08-ARTIFACT-IDENTITY`, `P08-PACKAGE-PARITY`,
`P08-RESOURCES-LICENSES`, `P08-PLAYER-STARTUP`, `P08-MAIN-DEFAULT-FRESH`,
`P08-UI-BUY-ONCE`, `P08-UI-SAVE-EXIT`, `P08-AUTORESTORE-PREINPUT`,
`P08-SECOND-UI-EXIT`, `P08-ISOLATION-CLEANUP`.

`mac_release_rendered` additionally requires `P08-NATIVE-VIEWPORT`. The canonical
render-lock FD must be inherited and held for the whole invocation. The QA never
grabs focus or changes geometry/time scale: actual fullscreen mode, focus,
content coverage and engine PNG dimensions must match. Four PNGs remain local.
Headless has no skipped render case and no pixel/fullscreen/device claim.

POSIX uses a fresh session/process group and the existing reviewed
`stop_owned_group` helper. Cleanup also checks descendants after parent exit;
needed cleanup is a failed normal-exit claim. Only that newly owned group is
signalled. Controlled child fixtures also verify an unrelated process survives.
The group mechanism does not claim containment of adversarial descendants that
create their own sessions; shipped/QA code is fixed and reviewed, not arbitrary
executable input.

Windows requires D02's fixed `tools/windows_process.ps1`, invoked by PowerShell 7:

```text
pwsh -NoProfile -File <helper> -RequestPath <local JSON> -ResultPath <local JSON>
```

Request keys are exactly `protocol="h06-owned-process-v1"`, `nonce`, `argv`
(string array), `cwd`, positive `timeout_seconds`, `log_path`. Return shape is
`ProcessExit` in the protocol schema: same protocol/nonce/argv/cwd, child PID,
start/end Unix nanoseconds, exit code, timeout/interruption, `ownership="windows_job"`,
`owned_empty`, cleanup signals, log SHA256. The helper must create suspended,
assign a kill-on-close Job before resume, bound waits, verify Job active count
zero and terminate only its Job. It must close the Job on wrapper cancellation;
wrapper exit 0 is not child-success evidence. Missing helper/support fails before
starting a release child. Windows execution is not proven by POSIX fixtures.

## CI output boundary

Only exact names in `contract-v1.json:upload_allowlist` may be selected for CI
upload. D02 must enumerate these names; no extension or directory wildcard.

- `native-result.json`, `build-metadata.json`, `fixture-report.json`: bounded
  result/identity/inventory/config/hash metadata. Metadata contains no source or
  package bytes; fixture results retain their synthetic classification.
- `capability-version.log`, `capability-help.log`: actual binary capability logs.
- `player-process.json`, `player-process.log`, `player-engine.log`: startup smoke.
- `purchase_save-observation.json`, `purchase_save-inputs.jsonl`,
  `purchase_save-process.json`, `purchase_save-process.log`,
  `purchase_save-engine.log`: first verification process evidence.
- `restore_exit-observation.json`, `restore_exit-inputs.jsonl`,
  `restore_exit-process.json`, `restore_exit-process.log`,
  `restore_exit-engine.log`: independent restore process evidence.

Observation snapshots come only from the new QA namespace's runtime state. Raw
userdata primary/backup files stay in temporary CI storage; the host reads them
there but never copies them into upload outputs. `manifest.json`, requests,
`restore-expected.json`, Windows `.job-request.json`/`.job-result.json` and viewport
PNGs are local-only. EXE/PCK/ZIP/templates, their encoded/encrypted forms, source
copies and arbitrary userdata are not report outputs. Failure never broadens
this whitelist. Windows work runs only in the current repository's temporary CI.

H06 can parse-check QA with the existing pinned editor's `--headless --script
... --check-only` without instantiating Main. That check is explicitly editor
syntax evidence. Actual release compilation, platform package layout, effective
settings, runtime InputEvent routing and native pixels remain D02/P08 checks.
