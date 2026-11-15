<#
  Conferir.ps1 - passo 5. Confere, linha a linha do plano.csv, se cada arquivo está no destino
  com o mesmo tamanho do inventário (e, nas cópias, se a origem está em _Para apagar\_Ja copiado...).
  Também compara número de arquivos e bytes de cada HD antes x depois.
#>
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
function Raiz($label) { $v = Get-Volume -FileSystemLabel $label | Where-Object DriveLetter | Select-Object -First 1; "$($v.DriveLetter):\" }
$HDC = Raiz 'HD_EXTERNO_CINZA'; $HDS = Raiz 'Seagate Expansion Drive'
$NomeHD = @{ $HDC = 'HD Cinza'; $HDS = 'Seagate' }; $Outro = @{ $HDC = $HDS; $HDS = $HDC }
function L([string]$p) { '\\?\' + $p }
function Info($p) { $f = New-Object IO.FileInfo (L $p); if ($f.Exists) { $f.Length } else { -1 } }

$inv = @{}
foreach ($n in 'Cinza', 'Seagate') { foreach ($r in (Import-Csv (Join-Path $base "inventario_$n.csv") -Delimiter ';')) { $inv[$r.caminho] = [int64]$r.tamanho } }
$plano = Import-Csv (Join-Path $base 'plano.csv') -Delimiter ';'
$problemas = New-Object System.Collections.Generic.List[string]
$ok = 0
foreach ($r in $plano) {
    if ($r.acao -eq 'REMOVER_SE_VAZIA') { continue }
    if ($r.acao -eq 'MOVER_PASTA') {
        if ([IO.Directory]::Exists((L $r.destino))) { $ok++ } elseif ([IO.Directory]::Exists((L $r.origem))) { $problemas.Add("NAO MOVIDA (ficou na origem): $($r.origem)") } else { $problemas.Add("PASTA SUMIU: $($r.origem)") }
        continue
    }
    $t = Info $r.destino
    if ($t -eq [int64]$r.tamanho) {
        if ($r.acao -eq 'COPIAR') {
            $hdO = $r.origem.Substring(0, 3)
            $lix = Join-Path $hdO ('_Para apagar\_Ja copiado para o ' + $NomeHD[$Outro[$hdO]] + '\' + $r.origem.Substring(3))
            if ((Info $lix) -ne [int64]$r.tamanho) { $problemas.Add("COPIA OK MAS ORIGEM NAO ESTA EM _Ja copiado: $($r.origem)") }
        }
        $ok++; continue
    }
    if ((Info $r.origem) -ge 0) { $problemas.Add("NAO MOVIDO (ficou na origem): $($r.origem)") }
    elseif ($t -ge 0) { $problemas.Add("TAMANHO DIFERENTE: $($r.destino) ($t x $($r.tamanho))") }
    else { $problemas.Add("NAO ENCONTRADO: $($r.origem) -> $($r.destino)") }
}

"Linhas do plano conferidas OK: $ok"
"Problemas: $($problemas.Count)"
$problemas | Select-Object -First 60
[IO.File]::WriteAllLines((Join-Path $base 'conferencia_problemas.txt'), $problemas, (New-Object Text.UTF8Encoding $true))
