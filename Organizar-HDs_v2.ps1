<#
  Organizar-HDs_v2.ps1 (deNoise, 14/11/2026) - aplica o plano.csv aprovado.

  Sem -Executar: SIMULA (confere origem, conflitos e espaço; não mexe em nada).
  Com -Executar: aplica, nesta ordem:
    1. caches -> _Para apagar
    2. movimentos dentro do mesmo HD (por cliente)
    3. cópias entre HDs: robocopy para <HD destino>\_entrada, confere tamanho de cada arquivo,
       move para o destino final e só então manda a origem para
       <HD origem>\_Para apagar\_Ja copiado para o <outro HD>\...
       Se a conferência falhar, a origem fica onde está.
    4. pastas vazias removidas (só as totalmente vazias)
  Nunca sobrescreve: se o destino existe, registra CONFLITO e pula.
  Log: log_<data>_<modo>.txt e movimentos_<data>.csv (origem;destino;acao;resultado) aqui e na raiz dos HDs.

  -Etapa  todas | caches | mover | copiar | vazias     (padrão: todas)
  -Cliente <nome>  limita a um cliente (lotes)
#>
param([switch]$Executar, [string]$Etapa = 'todas', [string]$Cliente = '')
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
# impede o Windows de dormir enquanto o script roda (ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
Add-Type -Namespace W -Name P -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[void][W.P]::SetThreadExecutionState([uint32]2147483649)
$Modo =if ($Executar) { 'execucao' } else { 'simulacao' }
$Carimbo = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$LogArq = Join-Path $base "log_${Carimbo}_$Modo.txt"
$MovArq = Join-Path $base "movimentos_${Carimbo}.csv"
$LogRobo = Join-Path $base "log_${Carimbo}_robocopy.txt"

function Raiz($label) { $v = Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue | Where-Object DriveLetter | Select-Object -First 1; if (-not $v) { throw "HD '$label' nao encontrado." }; "$($v.DriveLetter):\" }
$HDC = Raiz 'HD_EXTERNO_CINZA'; $HDS = Raiz 'Seagate Expansion Drive'
$NomeHD = @{ $HDC = 'HD Cinza'; $HDS = 'Seagate' }
$Outro = @{ $HDC = $HDS; $HDS = $HDC }

$script:Conta = @{ OK = 0; Pulado = 0; Conflito = 0; Erro = 0; Copiado = 0; Removida = 0 }
$script:Mov = New-Object System.Collections.Generic.List[string]
$script:Mov.Add('origem;destino;acao;resultado')

function Log($msg) { $linha = "$(Get-Date -Format 'HH:mm:ss') $msg"; Write-Host $linha; [IO.File]::AppendAllText($LogArq, $linha + "`r`n", [Text.Encoding]::UTF8) }
function Reg($o, $d, $a, $res) { $script:Mov.Add("$o;$d;$a;$res"); if ($script:Mov.Count % 200 -eq 0) { Salvar-Mov } }
function Salvar-Mov { [IO.File]::WriteAllLines($MovArq, $script:Mov, (New-Object Text.UTF8Encoding $true)) }
function L([string]$p) { if ($p.StartsWith('\\?\')) { $p } else { '\\?\' + $p } }
function ExisteArq($p) { [IO.File]::Exists((L $p)) }
function ExistePasta($p) { [IO.Directory]::Exists((L $p)) }
function Existe($p) { (ExisteArq $p) -or (ExistePasta $p) }
function GarantirPai($p) { $pai = [IO.Path]::GetDirectoryName($p); if (-not (ExistePasta $pai)) { [void][IO.Directory]::CreateDirectory((L $pai)) } }
function TamArq($p) { (New-Object IO.FileInfo (L $p)).Length }
function GB($b) { '{0:N1} GB' -f ($b / 1GB) }
function Livre($hd) { (Get-PSDrive -Name $hd.Substring(0, 1)).Free }

function Mover-Item($o, $d, $acao) {
    if (-not (Existe $o)) { Log "  [PULADO] nao existe: $o"; $script:Conta.Pulado++; Reg $o $d $acao 'PULADO'; return $false }
    if (Existe $d) { Log "  [CONFLITO] destino ja existe, nao sobrescrevi: $d"; $script:Conta.Conflito++; Reg $o $d $acao 'CONFLITO'; return $false }
    if (-not $Executar) { $script:Conta.OK++; return $true }
    try {
        GarantirPai $d
        if (ExisteArq $o) { [IO.File]::Move((L $o), (L $d)) } else { [IO.Directory]::Move((L $o), (L $d)) }
        $script:Conta.OK++; Reg $o $d $acao 'OK'; return $true
    } catch { Log "  [ERRO] $o -> $d : $($_.Exception.Message)"; $script:Conta.Erro++; Reg $o $d $acao 'ERRO'; return $false }
}

# ------------------------------------------------------------------ plano
$plano = Import-Csv (Join-Path $base 'plano.csv') -Delimiter ';'
if ($Cliente) { $plano = $plano | Where-Object { $_.cliente -eq $Cliente } }
Log "Organizar HDs v2 - $($Modo.ToUpper()) - Cinza=$HDC Seagate=$HDS - $($plano.Count) linhas - etapa=$Etapa cliente=$Cliente"

# Espaço para as cópias entre HDs
$precisa = @{ $HDC = [int64]0; $HDS = [int64]0 }
foreach ($r in $plano) { if ($r.acao -eq 'COPIAR') { $precisa[$r.destino.Substring(0, 3)] += [int64]$r.tamanho } }
$faltaEspaco = $false
foreach ($hd in $HDC, $HDS) {
    $livre = Livre $hd; $ok = $livre -gt ($precisa[$hd] + 2GB)
    Log ("  Chega no {0}: {1} | livre: {2} | {3}" -f $NomeHD[$hd], (GB $precisa[$hd]), (GB $livre), $(if ($ok) { 'OK' } else { 'NAO CABE' }))
    if (-not $ok) { $faltaEspaco = $true }
}

# Pastas-raiz
if ($Executar) {
    foreach ($hd in $HDC, $HDS) { foreach ($n in '01. Clientes', '02. Freelas', '03. Recursos de Edicao', '04. Pessoal', '90. A revisar', '99. Recuperados', '_Para apagar') { $p = Join-Path $hd $n; if (-not (ExistePasta $p)) { [void][IO.Directory]::CreateDirectory((L $p)) } } }
}

# ------------------------------------------------------------------ 1. caches
if ($Etapa -in 'todas', 'caches') {
    Log ''; Log '=== 1. Caches e lixo -> _Para apagar (mesmo HD)'
    foreach ($r in ($plano | Where-Object { $_.tipo -in 'cache', 'lixo' -and $_.acao -in 'MOVER', 'MOVER_PASTA' })) { [void](Mover-Item $r.origem $r.destino $r.acao) }
    Log ("  -> ok {0} | pulados {1} | conflitos {2} | erros {3}" -f $script:Conta.OK, $script:Conta.Pulado, $script:Conta.Conflito, $script:Conta.Erro)
}

# ------------------------------------------------------------------ 2. dentro do mesmo HD
if ($Etapa -in 'todas', 'mover') {
    Log ''; Log '=== 2. Reorganizacao dentro de cada HD'
    $movs = $plano | Where-Object { $_.acao -in 'MOVER', 'MOVER_PASTA' -and $_.tipo -notin 'cache', 'lixo' }
    foreach ($g in ($movs | Group-Object cliente | Sort-Object Name)) {
        $antes = $script:Conta.OK
        foreach ($r in $g.Group) { [void](Mover-Item $r.origem $r.destino $r.acao) }
        $nome = if ($g.Name) { $g.Name } else { '(pessoal/recursos/backups)' }
        Log ("  lote {0}: {1} itens, {2} ok | total: pulados {3} conflitos {4} erros {5}" -f $nome, $g.Count, ($script:Conta.OK - $antes), $script:Conta.Pulado, $script:Conta.Conflito, $script:Conta.Erro)
    }
}

# ------------------------------------------------------------------ 3. entre HDs
if ($Etapa -in 'todas', 'copiar') {
    Log ''; Log '=== 3. Copias entre HDs (robocopy + conferencia por tamanho)'
    if ($faltaEspaco) { Log '  [PARADO] espaco insuficiente em algum HD. Nada copiado.' }
    else {
        $copias = @($plano | Where-Object { $_.acao -eq 'COPIAR' })
        foreach ($g in ($copias | Group-Object cliente | Sort-Object Name)) {
            Log ("  lote {0}: {1} arquivos, {2}" -f $g.Name, $g.Count, (GB (($g.Group | ForEach-Object { [int64]$_.tamanho } | Measure-Object -Sum).Sum)))
            $okLote = 0
            # agrupa por pasta de origem para chamar o robocopy uma vez por pasta
            foreach ($gp in ($g.Group | Group-Object { [IO.Path]::GetDirectoryName($_.origem) })) {
                $srcDir = $gp.Name
                $hdO = $srcDir.Substring(0, 3); $hdD = $Outro[$hdO]
                $stage = Join-Path $hdD ('_entrada\' + $NomeHD[$hdO] + '\' + $srcDir.Substring(3))
                $validos = New-Object System.Collections.Generic.List[object]
                foreach ($r in $gp.Group) {
                    if (-not (ExisteArq $r.origem)) { Log "  [PULADO] nao existe: $($r.origem)"; $script:Conta.Pulado++; Reg $r.origem $r.destino 'COPIAR' 'PULADO'; continue }
                    if (Existe $r.destino) { Log "  [CONFLITO] destino ja existe: $($r.destino)"; $script:Conta.Conflito++; Reg $r.origem $r.destino 'COPIAR' 'CONFLITO'; continue }
                    $validos.Add($r)
                }
                if ($validos.Count -eq 0) { continue }
                if (-not $Executar) { $script:Conta.OK += $validos.Count; continue }
                # robocopy em blocos (limite de tamanho da linha de comando)
                $nomes = @($validos | ForEach-Object { [IO.Path]::GetFileName($_.origem) })
                $i = 0
                while ($i -lt $nomes.Count) {
                    $bloco = New-Object System.Collections.Generic.List[string]; $len = 0
                    while ($i -lt $nomes.Count -and $len -lt 20000) { $bloco.Add($nomes[$i]); $len += $nomes[$i].Length + 3; $i++ }
                    $args = @($srcDir, $stage) + $bloco + @('/COPY:DAT', '/DCOPY:T', '/R:2', '/W:5', '/XC', '/XN', '/XO', '/NP', '/NFL', '/NDL', "/LOG+:$LogRobo")
                    & robocopy @args | Out-Null
                    if ($LASTEXITCODE -ge 8) { Log "  [ERRO] robocopy codigo $LASTEXITCODE em $srcDir (veja $LogRobo)" }
                }
                foreach ($r in $validos) {
                    $nome = [IO.Path]::GetFileName($r.origem); $st = Join-Path $stage $nome
                    $tO = TamArq $r.origem
                    if (-not (ExisteArq $st) -or (TamArq $st) -ne $tO) { Log "  [ATENCAO] nao conferiu, origem mantida: $($r.origem)"; $script:Conta.Erro++; Reg $r.origem $r.destino 'COPIAR' 'NAO CONFERIU'; continue }
                    try {
                        GarantirPai $r.destino; [IO.File]::Move((L $st), (L $r.destino))
                        $lix = Join-Path $hdO ('_Para apagar\_Ja copiado para o ' + $NomeHD[$hdD] + '\' + $r.origem.Substring(3))
                        GarantirPai $lix; [IO.File]::Move((L $r.origem), (L $lix))
                        $script:Conta.Copiado++; $okLote++; Reg $r.origem $r.destino 'COPIAR' "OK (origem em $lix)"
                    } catch { Log "  [ERRO] $($r.origem): $($_.Exception.Message)"; $script:Conta.Erro++; Reg $r.origem $r.destino 'COPIAR' 'ERRO' }
                }
            }
            Log ("    -> {0} copiados e conferidos | erros acumulados {1}" -f $okLote, $script:Conta.Erro)
            Salvar-Mov
        }
    }
}

# ------------------------------------------------------------------ 4. pastas vazias
function Remover-Vazias($p) {
    if (-not (ExistePasta $p)) { return }
    try { $subs = [IO.Directory]::GetDirectories((L $p)) } catch { Log "  [SEM ACESSO] $p (deixei como esta)"; return }
    foreach ($sub in $subs) { Remover-Vazias $sub.Substring(4) }
    if ([IO.Directory]::GetFileSystemEntries((L $p)).Count -eq 0) {
        if ($Executar) {
            try { (New-Object IO.DirectoryInfo (L $p)).Attributes = 'Directory'; [IO.Directory]::Delete((L $p)); $script:Conta.Removida++ } catch { Log "  [ERRO] nao removi $p : $($_.Exception.Message)" }
        } else { $script:Conta.Removida++ }
    }
}
if ($Etapa -in 'todas', 'vazias') {
    Log ''; Log '=== 4. Pastas vazias'
    $origens = @('00. Marca Página', '01. Separ.acoes', '03. Hypper', '05. Freelas', 'Beatriz_Reels', 'Curso_Advocacia 6D', 'Nailde_reels', 'Nova pasta', 'Varandagem', '_entrada') | ForEach-Object { Join-Path $HDC $_ }
    $origens += @('Desktop', 'Program Files', 'WindowsApps', '_entrada') | ForEach-Object { Join-Path $HDS $_ }
    foreach ($o in $origens) { Remover-Vazias $o }
    Log "  pastas vazias removidas: $($script:Conta.Removida)"
    foreach ($o in $origens) { if (ExistePasta $o) { try { $n = @([IO.Directory]::GetFiles((L $o), '*', 'AllDirectories')).Count } catch { $n = -1 }; if ($n -gt 0) { Log "  [SOBROU] $o ainda tem $n arquivo(s)" } } }
}

# ------------------------------------------------------------------ resumo
Log ''
Log ("Resumo: movidos {0} | copiados entre HDs {1} | pulados {2} | conflitos {3} | erros {4} | pastas vazias {5}" -f $script:Conta.OK, $script:Conta.Copiado, $script:Conta.Pulado, $script:Conta.Conflito, $script:Conta.Erro, $script:Conta.Removida)
Salvar-Mov
if ($Executar) { foreach ($hd in $HDC, $HDS) { Copy-Item -LiteralPath $LogArq, $MovArq -Destination $hd -Force } }
Log "Log: $LogArq"
