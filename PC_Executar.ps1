<#
  PC_Executar.ps1 - aplica pc_plano.csv.
  Ordem: MAC (cópias) -> COPIAR (transfere: copia, confere tamanho, apaga original) -> COPIAR_MANTER
         -> REVISAR / APAGAR / DUPLICATA / JA_NO_HD (movem dentro do mesmo disco) -> pastas vazias.
  Nunca sobrescreve: destino existente com mesmo tamanho = já copiado (retomada); tamanho diferente = CONFLITO, original fica.
  Sem -Executar só simula.
#>
param([switch]$Executar)
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$mov = "$base\pc_movimentos_$stamp.csv"
$log = "$base\pc_log_$stamp.txt"
$wLog = New-Object IO.StreamWriter($log, $true, [Text.Encoding]::UTF8); $wLog.AutoFlush = $true
$wMov = New-Object IO.StreamWriter($mov, $false, [Text.Encoding]::UTF8); $wMov.AutoFlush = $true
function Log($m) { $l = "$(Get-Date -Format "HH:mm:ss") $m"; $wLog.WriteLine($l); Write-Host $l }
function L([string]$p) { if ($p.StartsWith('\\?\')) { $p } else { '\\?\' + $p } }
function Existe($p) { [IO.File]::Exists((L $p)) }
function Tam($p) { (New-Object IO.FileInfo (L $p)).Length }
function Livre($p) { (New-Object IO.DriveInfo ($p.Substring(0, 1))).AvailableFreeSpace }
$wMov.WriteLine("origem;destino;acao;resultado")
function Reg($o, $d, $a, $r) { $wMov.WriteLine("$o;$d;$a;$r") }

$plano = Import-Csv "$base\pc_plano.csv" -Delimiter ';'
Log "Modo: $(if($Executar){'EXECUCAO'}else{'SIMULACAO'}) - $($plano.Count) linhas"
$cont = @{}
function Conta($k) { if (-not $cont.ContainsKey($k)) { $cont[$k] = 0 }; $cont[$k]++ }

function Copiar($o, $d) {
    if (-not (Existe $o)) { return 'ORIGEM SUMIU' }
    $t = Tam $o
    if (Existe $d) { if ((Tam $d) -eq $t) { return 'JA COPIADO' } else { return 'CONFLITO' } }
    if (-not $Executar) { return 'OK (simulado)' }
    if ((Livre $d) - $t -lt 3GB) { throw "SEM ESPACO em $($d.Substring(0,2)) para $o" }
    [void][IO.Directory]::CreateDirectory((L ([IO.Path]::GetDirectoryName($d))))
    [IO.File]::Copy((L $o), (L $d), $false)
    if ((Tam $d) -ne $t) { [IO.File]::Delete((L $d)); return 'FALHA CONFERENCIA' }
    'OK'
}
function Mover($o, $d) {
    if (-not (Existe $o)) { return 'ORIGEM SUMIU' }
    if (Existe $d) { return 'CONFLITO' }
    if (-not $Executar) { return 'OK (simulado)' }
    [void][IO.Directory]::CreateDirectory((L ([IO.Path]::GetDirectoryName($d))))
    [IO.File]::Move((L $o), (L $d)); 'OK'
}
function ApagarOriginal($o) {
    if (-not $Executar) { return }
    $fi = New-Object IO.FileInfo (L $o)
    if ($fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $fi.Delete()
}

$i = 0
foreach ($fase in 'MAC', 'COPIAR', 'COPIAR_MANTER', 'MOVER') {
    $linhas = if ($fase -eq 'MOVER') { $plano | Where-Object { $_.acao -in 'REVISAR', 'APAGAR', 'DUPLICATA', 'JA_NO_HD' } } else { $plano | Where-Object acao -eq $fase }
    Log "== Fase $fase ($(@($linhas).Count) arquivos)"
    foreach ($r in $linhas) {
        $i++
        try {
            if ($fase -eq 'MOVER') { $res = Mover $r.origem $r.destino }
            else {
                $res = Copiar $r.origem $r.destino
                if ($fase -eq 'COPIAR' -and $res -in 'OK', 'JA COPIADO') { ApagarOriginal $r.origem; $res = "$res, original apagado" }
            }
        } catch {
            if ($_.Exception.Message -like 'SEM ESPACO*') { Log $_.Exception.Message; Reg $r.origem $r.destino $r.acao 'PARADO SEM ESPACO'; throw }
            $res = "ERRO: $($_.Exception.Message -replace ';', ',')"
        }
        Reg $r.origem $r.destino $r.acao $res
        Conta "$fase | $(($res -split ',')[0])"
        if ($res -notlike 'OK*' -and $res -notlike 'JA COPIADO*') { Log "  $res : $($r.origem)" }
        if ($i % 250 -eq 0) { Log "  ... $i linhas" }
    }
}

# pastas vazias nas áreas de trabalho que foram esvaziadas
if ($Executar) {
    $areas = 'D:\01. Trabalho', 'D:\vlog 04 julho', 'D:\Design sem nome', 'D:\00. Triagem', 'D:\Riot Games', 'D:\msdownld.tmp',
             'C:\Users\julia\Desktop\NGCASH', 'C:\Users\julia\Desktop\Tudo', 'C:\Users\julia\Desktop\vlog 02 - julho', 'C:\Users\julia\Desktop\0204_', 'C:\Users\julia\Desktop\workshop'
    $areas += Get-ChildItem C:\Users\julia\Downloads -Directory -Force | ForEach-Object FullName
    $n = 0
    foreach ($a in $areas) {
        if (-not (Test-Path -LiteralPath $a)) { continue }
        $dirs = @(Get-ChildItem -LiteralPath $a -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending) + @(Get-Item -LiteralPath $a -Force)
        foreach ($d in $dirs) {
            if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $d.FullName -Force; $n++ }
        }
    }
    Log "Pastas vazias removidas: $n"
    foreach ($hd in 'E:\', 'F:\') { Copy-Item $mov "$hd" ; Copy-Item $log "$hd" }
}
Log '== Resumo'
$cont.GetEnumerator() | Sort-Object Name | ForEach-Object { Log ('{0,-40} {1}' -f $_.Name, $_.Value) }
$wLog.Close(); $wMov.Close()
