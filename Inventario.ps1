<#
  Inventario.ps1 - passo 1 (só leitura). Gera inventario_<HD>.csv e um resumo por pasta de topo.
  Duração dos vídeos via propriedade do Windows (System.Media.Duration), sem precisar de ffprobe.
#>
param([switch]$SemDuracao)
$ErrorActionPreference = 'Stop'
$saida = $PSScriptRoot
$videos = '.mp4','.mov','.m4v','.mxf','.avi','.mkv','.mts','.wmv'

$shell = New-Object -ComObject Shell.Application
$pastasShell = @{}
function Duracao($f) {
    try {
        $dir = $f.DirectoryName
        if (-not $pastasShell.ContainsKey($dir)) { $pastasShell[$dir] = $shell.Namespace($dir) }
        $ns = $pastasShell[$dir]
        $it = $ns.ParseName($f.Name)
        $ticks = $it.ExtendedProperty('System.Media.Duration')
        if ($ticks) { return [math]::Round([double]$ticks / 1e7, 1) }
    } catch {}
    return ''
}

foreach ($label in 'HD_EXTERNO_CINZA', 'Seagate Expansion Drive') {
    $v = Get-Volume -FileSystemLabel $label | Where-Object DriveLetter | Select-Object -First 1
    $raiz = "$($v.DriveLetter):\"
    $nome = if ($label -like 'HD_*') { 'Cinza' } else { 'Seagate' }
    $csv = Join-Path $saida "inventario_$nome.csv"
    $linhas = New-Object System.Collections.Generic.List[string]
    $linhas.Add('caminho;tamanho;modificado;extensao;duracao_s')
    $n = 0
    Get-ChildItem -LiteralPath $raiz -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '^[A-Z]:\\(System Volume Information|\$RECYCLE\.BIN)' } |
        ForEach-Object {
            $ext = $_.Extension.ToLower()
            $dur = if (-not $SemDuracao -and $videos -contains $ext) { Duracao $_ } else { '' }
            $linhas.Add(('{0};{1};{2};{3};{4}' -f $_.FullName, $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $ext, $dur))
            $n++
        }
    [System.IO.File]::WriteAllLines($csv, $linhas, (New-Object System.Text.UTF8Encoding $true))
    "$nome ($raiz): $n arquivos -> $csv"
}
