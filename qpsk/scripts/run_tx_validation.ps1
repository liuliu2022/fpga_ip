param(
    [Parameter(Mandatory = $true)] [string] $MatlabExe,
    [Parameter(Mandatory = $true)] [string] $VivadoBin
)

$ErrorActionPreference = 'Stop'
$QpskDir = Split-Path -Parent $PSScriptRoot
$TxDir = Join-Path $QpskDir 'rtl\tx'
$RxDir = Join-Path $QpskDir 'rtl\rx'
$MatlabDir = Join-Path $QpskDir 'matlab'
$SimDir = Join-Path $QpskDir 'sim'

if (-not (Test-Path -LiteralPath $MatlabExe)) { throw "MATLAB not found: $MatlabExe" }
if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin 'xvlog.bat'))) { throw "Vivado bin not found: $VivadoBin" }
Set-Location -LiteralPath $SimDir

& $MatlabExe -batch "run('$($MatlabDir.Replace('\','/'))/design_tx_rrc.m'); run('$($MatlabDir.Replace('\','/'))/generate_tx_vectors.m')"
if ($LASTEXITCODE -ne 0) { throw 'MATLAB TX vector generation failed' }

& "$VivadoBin\xvlog.bat" -i $TxDir `
    "$TxDir\tx_qpsk_diff_encode.v" "$TxDir\tx_rrc_interp48x4.v" `
    "$TxDir\gowinsdr_tx_chain.v" "$SimDir\tb_gowinsdr_tx_chain.v"
if ($LASTEXITCODE -ne 0) { throw 'TX xvlog failed' }
& "$VivadoBin\xelab.bat" tb_gowinsdr_tx_chain -s tx_chain_snapshot
if ($LASTEXITCODE -ne 0) { throw 'TX xelab failed' }
& "$VivadoBin\xsim.bat" tx_chain_snapshot -runall
if ($LASTEXITCODE -ne 0) { throw 'TX xsim failed' }

& "$VivadoBin\xvlog.bat" -i $TxDir `
    "$TxDir\tx_qpsk_diff_encode.v" "$TxDir\tx_rrc_interp48x4.v" `
    "$TxDir\gowinsdr_tx_chain.v" "$TxDir\tx_prbs_qpsk_source.v" `
    "$RxDir\rx_polyphase_decim4.v" "$RxDir\rx_matched_rrc.v" `
    "$RxDir\rx_costas_loop.v" "$RxDir\rx_farrow_interpolator.v" `
    "$RxDir\rx_gardner_timing.v" "$RxDir\rx_qpsk_diff_decode.v" `
    "$RxDir\gowinsdr_rx_chain.v" "$SimDir\tb_tx_rx_loopback.v"
if ($LASTEXITCODE -ne 0) { throw 'Loopback xvlog failed' }
& "$VivadoBin\xelab.bat" tb_tx_rx_loopback -s tx_rx_loopback_snapshot
if ($LASTEXITCODE -ne 0) { throw 'Loopback xelab failed' }
& "$VivadoBin\xsim.bat" tx_rx_loopback_snapshot -runall
if ($LASTEXITCODE -ne 0) { throw 'Loopback xsim failed' }
