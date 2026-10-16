param(
    [Parameter(Mandatory = $true)] [string] $MatlabExe,
    [Parameter(Mandatory = $true)] [string] $VivadoBin
)

$ErrorActionPreference = 'Stop'
$QpskDir = Split-Path -Parent $PSScriptRoot
$RxDir = Join-Path $QpskDir 'rtl\rx'
$PacketDir = Join-Path $QpskDir 'rtl\packet'
$MatlabDir = Join-Path $QpskDir 'matlab'
$SimDir = Join-Path $QpskDir 'sim'

if (-not (Test-Path -LiteralPath $MatlabExe)) {
    throw "MATLAB not found: $MatlabExe"
}
if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin 'xvlog.bat'))) {
    throw "Vivado bin not found: $VivadoBin"
}

Set-Location -LiteralPath $SimDir

$MatlabScript = (Join-Path $MatlabDir 'generate_packet_iq_scenarios.m').Replace('\', '/')
& $MatlabExe -batch "run('$MatlabScript')"
if ($LASTEXITCODE -ne 0) { throw 'MATLAB packet I/Q generation failed' }

& "$VivadoBin\xvlog.bat" `
    "$RxDir\rx_polyphase_decim4.v" `
    "$RxDir\rx_matched_rrc.v" `
    "$RxDir\rx_costas_loop.v" `
    "$RxDir\rx_farrow_interpolator.v" `
    "$RxDir\rx_gardner_timing.v" `
    "$RxDir\rx_qpsk_diff_decode.v" `
    "$RxDir\gowinsdr_rx_chain.v" `
    "$PacketDir\axis_rx_deframer.v" `
    "$SimDir\tb_packet_iq_injection.v"
if ($LASTEXITCODE -ne 0) { throw 'Packet I/Q xvlog failed' }

$Cases = @(
    @{ Top = 'tb_packet_iq_baseline'; Snapshot = 'packet_iq_baseline_snapshot' },
    @{ Top = 'tb_packet_iq_phase90';  Snapshot = 'packet_iq_phase90_snapshot' },
    @{ Top = 'tb_packet_iq_combined'; Snapshot = 'packet_iq_combined_snapshot' },
    @{ Top = 'tb_packet_iq_low_amp_20'; Snapshot = 'packet_iq_low_amp_20_snapshot' }
)

foreach ($Case in $Cases) {
    & "$VivadoBin\xelab.bat" $Case.Top -s $Case.Snapshot
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $($Case.Top)" }
    & "$VivadoBin\xsim.bat" $Case.Snapshot -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed: $($Case.Top)" }
}

Write-Host 'PASS: all MATLAB-generated packet I/Q injection cases completed'
