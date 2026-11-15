<#
  PC_Relatorio.ps1 - depois da execução: gera
   - PARA_O_MAC.md (vai pro GitHub; repo é público -> sem nomes de documentos/pessoal)
   - ONDE_FOI_PC.md (resumo por cliente/pasta; fica no PC e nos HDs)
#>
param([string]$Movimentos)
$base = $PSScriptRoot
$m = Import-Csv $Movimentos -Delimiter ';'
$ok = $m | Where-Object { $_.resultado -like 'OK*' -or $_.resultado -like 'JA COPIADO*' }
function GB($b) { '{0:N1} GB' -f ($b / 1GB) }
function Tam($p) { try { (New-Object IO.FileInfo ('\\?\' + $p)).Length } catch { 0 } }

# ---------------- PARA_O_MAC.md
$mac = 'D:\05. Para o Mac'
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('# Para o Mac')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm') no PC Windows. Tudo abaixo esta em **D:\05. Para o Mac** (copias; os originais foram pro backup ou ficaram no PC).")
[void]$sb.AppendLine('Plugue o SSD ou copie pela rede e pegue o que quiser.')
[void]$sb.AppendLine('')
foreach ($top in Get-ChildItem $mac -Directory | Sort-Object Name) {
    $fs = Get-ChildItem -LiteralPath $top.FullName -Recurse -File -Force
    [void]$sb.AppendLine("## $($top.Name) ($(GB ($fs | Measure-Object Length -Sum).Sum), $($fs.Count) arquivos)")
    [void]$sb.AppendLine('')
    if ($top.Name -like 'deNoise*') {
        foreach ($f in $fs | Sort-Object Name) { [void]$sb.AppendLine("- $($f.Name)") }
        [void]$sb.AppendLine(''); continue
    }
    # lista por subpasta (até 2 níveis) com tamanho; arquivos soltos listados se forem poucos
    $subs = Get-ChildItem -LiteralPath $top.FullName -Directory
    foreach ($s in $subs | Sort-Object Name) {
        $sf = Get-ChildItem -LiteralPath $s.FullName -Recurse -File -Force
        [void]$sb.AppendLine("- **$($s.Name)/** - $(GB ($sf | Measure-Object Length -Sum).Sum), $($sf.Count) arquivos")
        if ($top.Name -eq 'Clientes') {
            foreach ($s2 in Get-ChildItem -LiteralPath $s.FullName -Directory | Sort-Object Name) {
                $sf2 = Get-ChildItem -LiteralPath $s2.FullName -Recurse -File -Force
                [void]$sb.AppendLine("  - $($s2.Name)/ - $($sf2.Count) arquivos")
            }
            foreach ($f in Get-ChildItem -LiteralPath $s.FullName -File | Sort-Object Name) { [void]$sb.AppendLine("  - $($f.Name)") }
        }
    }
    foreach ($f in Get-ChildItem -LiteralPath $top.FullName -File | Sort-Object Name) { [void]$sb.AppendLine("- $($f.Name) ($('{0:N1}' -f ($f.Length/1MB)) MB)") }
    [void]$sb.AppendLine('')
}
# projetos recentes (desde agosto/2026) que foram pro backup
$proj = $ok | Where-Object { $_.acao -eq 'COPIAR' -and $_.destino -match '(?i)\.(prproj|aep|drp)$' } | ForEach-Object {
    $fi = New-Object IO.FileInfo ('\\?\' + $_.destino); [pscustomobject]@{ D = $_.destino; T = $fi.LastWriteTime } } | Where-Object { $_.T -ge [datetime]'2026-08-01' } | Sort-Object T -Descending
[void]$sb.AppendLine("## Projetos recentes (desde 08/2026) que foram pro backup")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Nao copiei pro Mac (os links de midia quebram e os brutos ficaram no PC). Se precisar de algum, ele esta neste caminho no HD:')
[void]$sb.AppendLine('')
$hdNome = @{ 'E' = 'HD Cinza'; 'F' = 'Seagate' }
foreach ($p in $proj) { [void]$sb.AppendLine("- $($p.T.ToString('dd/MM')) - $($hdNome[$p.D.Substring(0,1)]): ``$($p.D.Substring(3))``") }
[System.IO.File]::WriteAllText("$base\PARA_O_MAC.md", $sb.ToString(), (New-Object Text.UTF8Encoding $false))

# ---------------- ONDE_FOI_PC.md
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('# Onde foi parar o trabalho do PC Windows')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Transferencia feita em $(Get-Date -Format 'dd/MM/yyyy'). A lista arquivo por arquivo (origem -> destino) esta em ``$(Split-Path $Movimentos -Leaf)`` (no repo, na raiz do HD Cinza e na raiz do Seagate). Abra no Excel e filtre pela coluna origem pra achar qualquer arquivo.")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Destino | Arquivos | Tamanho |')
[void]$sb.AppendLine('|---|---:|---:|')
$grp = $ok | Where-Object { $_.acao -like 'COPIAR*' } | Group-Object { $parts = $_.destino.Split('\'); "$($hdNome[$parts[0].Substring(0,1)]) \ $($parts[1]) \ $($parts[2])" } | Sort-Object Name
foreach ($g in $grp) { $b = ($g.Group | ForEach-Object { Tam $_.destino } | Measure-Object -Sum).Sum; [void]$sb.AppendLine("| $($g.Name) | $($g.Count) | $(GB $b) |") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('**Ficou no PC:**')
foreach ($d in 'D:\90. A revisar', 'C:\90. A revisar', 'D:\_Para apagar', 'C:\_Para apagar', 'D:\05. Para o Mac') {
    if (Test-Path -LiteralPath $d) { $fs = Get-ChildItem -LiteralPath $d -Recurse -File -Force; [void]$sb.AppendLine("- ``$d`` - $($fs.Count) arquivos, $(GB ($fs | Measure-Object Length -Sum).Sum)") }
}
[System.IO.File]::WriteAllText("$base\ONDE_FOI_PC.md", $sb.ToString(), (New-Object Text.UTF8Encoding $false))
Write-Host 'ok'
