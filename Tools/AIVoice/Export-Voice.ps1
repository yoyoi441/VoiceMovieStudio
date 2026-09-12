# Windows PowerShell 5.1, run in the signed-in desktop user's session.
# First-generation A.I.VOICE only. No network listener; no product binaries bundled.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ApiDll,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$TextFile,
    [string]$VoicePreset,
    [string]$EditorHost,
    [switch]$ListPresets,
    [switch]$AcceptApiTerms
)
$ErrorActionPreference = 'Stop'
if (-not $AcceptApiTerms) { throw 'Read the product and Editor API terms, then supply -AcceptApiTerms.' }
if (-not $ListPresets -and -not $TextFile) { throw 'Specify a UTF-8 -TextFile or -ListPresets.' }
$assembly = (Resolve-Path -LiteralPath $ApiDll).Path
if ([IO.Path]::GetFileName($assembly) -ne 'AI.Talk.Editor.Api.dll') {
    throw 'Select the installed official AI.Talk.Editor.Api.dll.'
}
Add-Type -Path $assembly
$control = New-Object AI.Talk.Editor.Api.TtsControl
$mutex = New-Object Threading.Mutex($false, 'Local\VMS_AIVoice_Export')
$owned = $false
$connected = $false
$restore = $false
try {
    $owned = $mutex.WaitOne(0)
    if (-not $owned) { throw 'Another VMS export is running.' }
    $hosts = @($control.GetAvailableHostNames())
    if ($hosts.Count -eq 0) { throw 'No A.I.VOICE Editor found. Version 2 is not supported by this API.' }
    if (-not $EditorHost) {
        if ($hosts.Count -ne 1) { throw ('Specify -EditorHost: ' + ($hosts -join ', ')) }
        $EditorHost = $hosts[0]
    }
    if ($hosts -notcontains $EditorHost) { throw 'Unknown -EditorHost.' }
    $control.Initialize($EditorHost)
    if ($control.Status.ToString() -eq 'NotRunning') { $control.StartHost() }
    $control.Connect()
    $connected = $true
    if ($control.Status.ToString() -ne 'Idle') { throw 'Editor is busy. Finish playback/export and try again.' }
    if ($ListPresets) {
        $control.VoicePresetNames
        return
    }
    $source = (Resolve-Path -LiteralPath $TextFile).Path
    if ((Get-Item -LiteralPath $source).Length -gt 1000000) { throw 'Text file is too large.' }
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $text = [IO.File]::ReadAllText($source, $utf8).Trim()
    if (-not $text) { throw 'Text file is empty.' }
    if ($VoicePreset -and @($control.VoicePresetNames) -notcontains $VoicePreset) {
        throw 'Unknown voice preset. Use -ListPresets first.'
    }
    $oldMode = $control.TextEditMode
    $oldText = $control.Text
    $oldStart = $control.TextSelectionStart
    $oldLength = $control.TextSelectionLength
    $oldPreset = $control.CurrentVoicePresetName
    $restore = $true
    $control.TextEditMode = [AI.Talk.Editor.Api.TextEditMode]::Text
    if ($VoicePreset) { $control.CurrentVoicePresetName = $VoicePreset }
    $control.Text = $text
    $control.TextSelectionStart = 0
    $control.TextSelectionLength = 0
    $destination = [IO.Path]::GetFullPath($OutputDirectory)
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    $name = 'voice_' + [Guid]::NewGuid().ToString('N')
    $staging = Join-Path $destination ('.vms-' + $name)
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    $wav = Join-Path $staging ($name + '.wav')
    # Synchronous. Host voice effects/save settings apply. Do not edit Editor until finished.
    $control.SaveAudioToFile($wav)
    $generated = @(Get-ChildItem -LiteralPath $staging -Filter '*.wav')
    if (-not (Test-Path -LiteralPath $wav) -or $generated.Count -ne 1) {
        throw ('Configure Editor to save a single WAV (no splitting). Output retained at: ' + $staging)
    }
    [IO.File]::WriteAllText((Join-Path $destination ($name + '.txt')), $text, $utf8)
    # Publish WAV last, after synthesis and subtitle output are complete.
    [IO.File]::Move($wav, (Join-Path $destination ($name + '.wav')))
    Write-Output (Join-Path $destination ($name + '.wav'))
    # Keep any additional product-generated metadata in the hidden staging directory.
} finally {
    if ($restore) {
        try {
            $control.Text = $oldText
            $control.TextSelectionStart = $oldStart
            $control.TextSelectionLength = $oldLength
            $control.CurrentVoicePresetName = $oldPreset
            $control.TextEditMode = $oldMode
        } catch { Write-Warning 'Editor state could not be restored. Check the Editor window.' }
    }
    if ($connected) { try { $control.Disconnect() } catch {} }
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
