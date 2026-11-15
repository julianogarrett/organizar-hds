<#
  Organizar-HDs.ps1 (deNoise, 24/10/2026)
  Reorganiza o HD_EXTERNO_CINZA e o Seagate Expansion Drive na hierarquia combinada:

    00. LEIA-ME.txt
    01. Clientes\        02. Freelas\          03. Recursos de Edição\
    04. Pessoal\         05. Backups de Computador\
    90. A triar\         99. Recuperados\      _Para apagar\

  Seagate = Marca Página + Pessoal + Backups.  Cinza = os outros clientes e Freelas.

  REGRAS
  - Sem -Executar ele só SIMULA: lista cada passo e não mexe em nada.
  - Nada é apagado. O que sobra vai para "_Para apagar" no próprio HD, com o
    caminho original, para o Juliano revisar e esvaziar.
  - Entre HDs: copia com robocopy, confere arquivo por arquivo (tamanho) e só
    então manda a origem para "_Para apagar". Se a conferência falhar, a origem fica.
  - Se o destino já tem um arquivo com o mesmo nome, não sobrescreve: registra CONFLITO.
  - Só pastas totalmente vazias são removidas.

  USO (PowerShell no Windows, na pasta do script)
    powershell -ExecutionPolicy Bypass -File .\Organizar-HDs.ps1             # simulação
    powershell -ExecutionPolicy Bypass -File .\Organizar-HDs.ps1 -Executar   # para valer
#>
param([switch]$Executar)

$ErrorActionPreference = 'Stop'
$Modo = if ($Executar) { 'EXECUÇÃO' } else { 'SIMULAÇÃO' }
$Carimbo = Get-Date -Format 'yyyy-MM-dd_HHmm'
$LogArq = Join-Path $PSScriptRoot "log_${Carimbo}_$($Modo.ToLower()).txt"
$LogRobo = Join-Path $PSScriptRoot "log_${Carimbo}_robocopy.txt"

# Na simulação, cada passo vira uma operação virtual; Resolver() traduz um caminho do
# "estado futuro" de volta para onde ele está hoje no disco.
$script:Ops = New-Object System.Collections.Generic.List[object]
$script:Conta = @{ Mover = 0; Copiar = 0; Lixeira = 0; Pulado = 0; Conflito = 0; Erro = 0 }
$script:BytesPara = @{}

function Log($msg) {
    Write-Host $msg
    Add-Content -LiteralPath $LogArq -Value $msg -Encoding UTF8
}

function Get-Raiz($label) {
    $v = Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue | Where-Object DriveLetter | Select-Object -First 1
    if (-not $v) { throw "HD '$label' não encontrado. Conecte os dois HDs e rode de novo." }
    return "$($v.DriveLetter):\"
}

function Unidade($p) { return $p.Substring(0, 3).ToUpper() }

function Sob($p, $base) {
    return ($p -eq $base) -or $p.StartsWith("$base\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolver($p) {
    $p = $p.TrimEnd('\')
    for ($i = $script:Ops.Count - 1; $i -ge 0; $i--) {
        $op = $script:Ops[$i]
        switch ($op.Tipo) {
            'Mover' {
                if (Sob $p $op.Para) { $p = $op.De + $p.Substring($op.Para.Length) }
                elseif (Sob $p $op.De) { return $null }
            }
            'Copia' { if (Sob $p $op.Para) { $p = $op.De + $p.Substring($op.Para.Length) } }
            'Criar' { if ($p -eq $op.Para) { return 'VIRTUAL' } elseif (Sob $p $op.Para) { return $null } }
            'Remover' { if (Sob $p $op.Para) { return $null } }
        }
    }
    return $p
}

# Uma pasta que só "existe" porque algo foi movido para dentro dela.
function PaiImplicito($p) {
    $p = $p.TrimEnd('\')
    foreach ($op in $script:Ops) {
        if ($op.Para -ne $p -and (Sob $op.Para $p)) {
            $r = Resolver $op.Para
            if (($r -eq 'VIRTUAL') -or ($r -and (Test-Path -LiteralPath $r))) { return $true }
        }
    }
    return $false
}

function Existe($p) {
    $r = Resolver $p
    return ($r -eq 'VIRTUAL') -or ($r -and (Test-Path -LiteralPath $r)) -or (PaiImplicito $p)
}

function EhPasta($p) {
    $r = Resolver $p
    return ($r -eq 'VIRTUAL') -or ($r -and (Test-Path -LiteralPath $r -PathType Container)) -or (PaiImplicito $p)
}

function Op($tipo, $para, $de = $null) {
    if ($de) { $de = $de.TrimEnd('\') }
    $script:Ops.Add([pscustomobject]@{ Tipo = $tipo; Para = $para.TrimEnd('\'); De = $de })
}

function Marcar($de, $para) { Op 'Mover' $para $de }

function Garantir-Pasta($p) {
    if (Existe $p) { return }
    if ($Executar) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    else { Op 'Criar' $p }
}

function Tamanho($p) {
    $p = Resolver $p
    if (-not $p -or $p -eq 'VIRTUAL') { return 0 }
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Item -LiteralPath $p -Force).Length }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($s) { return [int64]$s } else { return 0 }
}

function GB($b) { return '{0:N1} GB' -f ($b / 1GB) }

# Move dentro do mesmo HD (é só renomear, instantâneo). Se o destino já existe e as
# duas coisas são pastas, mescla o conteúdo item a item.
function Mover($de, $para) {
    if (-not (Existe $de)) { Log "  [PULADO] não existe: $de"; $script:Conta.Pulado++; return }
    if ((Unidade $de) -ne (Unidade $para)) { throw "Mover() entre HDs diferentes: $de -> $para" }
    if (Existe $para) {
        if ((EhPasta $de) -and (EhPasta $para)) {
            $real = Resolver $de
            if ($real -and $real -ne 'VIRTUAL' -and (Test-Path -LiteralPath $real)) {
                foreach ($f in Get-ChildItem -LiteralPath $real -Force) {
                    $filho = Join-Path $de $f.Name
                    if (Existe $filho) { Mover $filho (Join-Path $para $f.Name) }
                }
            }
            if ($Executar) { if (-not (Get-ChildItem -LiteralPath $de -Force)) { Remove-Item -LiteralPath $de -Force } }
            else { Op 'Remover' $de }
            return
        }
        Log "  [CONFLITO] já existe, não sobrescrevi: $para"; $script:Conta.Conflito++; return
    }
    Log "  [MOVER] $de  ->  $para"
    $script:Conta.Mover++
    if ($Executar) {
        try {
            $pai = Split-Path -Parent $para
            if (-not (Test-Path -LiteralPath $pai)) { New-Item -ItemType Directory -Path $pai -Force | Out-Null }
            Move-Item -LiteralPath $de -Destination $para
        } catch { Log "  [ERRO] $($_.Exception.Message)"; $script:Conta.Erro++ }
    } else { Marcar $de $para }
}

# Manda para "_Para apagar" do mesmo HD, mantendo o caminho original.
function Lixeira($p) {
    if (-not (Existe $p)) { Log "  [PULADO] não existe: $p"; $script:Conta.Pulado++; return }
    $destino = Join-Path ((Unidade $p) + '_Para apagar') $p.Substring(3)
    Log "  [PARA APAGAR] $p"
    $script:Conta.Lixeira++
    if ($Executar) {
        try {
            $pai = Split-Path -Parent $destino
            if (-not (Test-Path -LiteralPath $pai)) { New-Item -ItemType Directory -Path $pai -Force | Out-Null }
            Move-Item -LiteralPath $p -Destination $destino
        } catch { Log "  [ERRO] $($_.Exception.Message)"; $script:Conta.Erro++ }
    } else { Marcar $p $destino }
}

# Copia de um HD para o outro, confere e manda a origem para "_Para apagar".
function Copiar-Entre-HDs($de, $para) {
    if (-not (Existe $de)) { Log "  [PULADO] não existe: $de"; $script:Conta.Pulado++; return }
    $bytes = Tamanho $de
    $u = Unidade $para
    $script:BytesPara[$u] = [int64]$script:BytesPara[$u] + $bytes
    Log "  [COPIAR ENTRE HDs] $de  ->  $para  ($(GB $bytes))"
    $script:Conta.Copiar++
    if (-not $Executar) {
        Lixeira $de
        Op 'Copia' $para (Join-Path ((Unidade $de) + '_Para apagar') $de.Substring(3))
        return
    }

    robocopy "$de" "$para" /E /COPY:DAT /DCOPY:T /R:2 /W:5 /XC /XN /XO /NP /NFL /NDL "/LOG+:$LogRobo" | Out-Null
    if ($LASTEXITCODE -ge 8) { Log "  [ERRO] robocopy falhou (código $LASTEXITCODE). Origem mantida. Veja $LogRobo"; $script:Conta.Erro++; return }

    $falhas = 0
    foreach ($f in Get-ChildItem -LiteralPath $de -Recurse -File -Force) {
        $alvo = Join-Path $para $f.FullName.Substring($de.Length).TrimStart('\')
        if (-not (Test-Path -LiteralPath $alvo) -or (Get-Item -LiteralPath $alvo -Force).Length -ne $f.Length) {
            $falhas++
            if ($falhas -le 10) { Log "    diferente/faltando: $alvo" }
        }
    }
    if ($falhas -gt 0) { Log "  [ATENÇÃO] $falhas arquivo(s) não conferem. Origem mantida em $de"; $script:Conta.Erro++; return }
    Log "    conferido: todos os arquivos chegaram com o mesmo tamanho"
    Lixeira $de
}

# Usado no fim de cada bloco: se a pasta sobrou vazia, remove; se sobrou coisa, move o resto.
function Mover-Resto($de, $para) {
    if (-not (Existe $de)) { return }
    if (-not $Executar) { Log "  [O QUE SOBRAR] $de  ->  $para (ou remove, se estiver vazia)"; Marcar $de $para; return }
    if (-not (Get-ChildItem -LiteralPath $de -Recurse -File -Force -ErrorAction SilentlyContinue)) { Remover-SeVazia $de; return }
    Mover $de $para
}

function Remover-SeVazia($p) {
    if (-not (Existe $p)) { return }
    if (-not $Executar) { Log "  [REMOVER SE VAZIA] $p"; Op 'Remover' $p; return }
    if (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue) { Log "  [MANTIDA, tem arquivos] $p"; return }
    try { Remove-Item -LiteralPath $p -Recurse -Force; Log "  [REMOVIDA, vazia] $p" }
    catch { Log "  [ERRO] não consegui remover $p : $($_.Exception.Message)"; $script:Conta.Erro++ }
}

function Etapa($t) { Log ''; Log "=== $t" }

# ---------------------------------------------------------------------------
$C = Get-Raiz 'HD_EXTERNO_CINZA'
$S = Get-Raiz 'Seagate Expansion Drive'

Log "Organizar HDs - $Modo - $(Get-Date)"
Log "Cinza = $C   Seagate = $S"
if (-not $Executar) { Log 'Nada será alterado. Rode com -Executar para aplicar.' }

# Caminhos de origem
$SD   = "${S}Desktop"
$SP   = "$SD\00_Projetos Ativos"
$SMP  = "$SP\Marca Página"
$SMP0 = "$SMP\00. Marca Página"
$CMP  = "${C}00. Marca Página"
$CFr  = "$CMP\05. Frame"

# Destinos
$MP   = "${S}01. Clientes\Marca Página"
$EMP  = "$MP\_entrada HD Cinza"
$V    = "${C}01. Clientes\Vivi - Histórias de Divórcio"
$VV   = "$V\00. Vídeos"
$HY   = "${C}01. Clientes\Hypper"
$ALE  = "${C}01. Clientes\Ale Busato - Advocacia 6D"

Etapa '0. Pastas-raiz'
foreach ($r in @($C, $S)) {
    foreach ($n in '01. Clientes', '02. Freelas', '03. Recursos de Edição', '04. Pessoal', '05. Backups de Computador', '90. A triar', '99. Recuperados', '_Para apagar') {
        Garantir-Pasta (Join-Path $r $n)
    }
}

Etapa '1. Caches do Premiere/After Effects -> _Para apagar'
$caches = 'Adobe Premiere Pro Audio Previews', 'Adobe Premiere Pro Video Previews', 'Adobe Premiere Pro Auto-Save', 'Adobe Premiere Pro (Beta) Auto-Save', 'Adobe After Effects Auto-Save'
foreach ($r in @($C, $S)) {
    $achados = Get-ChildItem -LiteralPath $r -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $caches -contains $_.Name -and -not (Sob $_.FullName (Join-Path $r '_Para apagar')) } |
        Sort-Object { $_.FullName.Length }
    foreach ($d in $achados) { if (Existe $d.FullName) { Lixeira $d.FullName } }
}

# ----------------------------- HD CINZA (interno) --------------------------
Etapa '2. Cinza: Separ.acoes vira "Vivi - Histórias de Divórcio", organizado por pessoa'
Mover "${C}01. Separ.acoes" $V

# Tatiane
Mover "$V\tatiane_YT_final.mp4"     "$V\Tatiane\YouTube\tatiane_YT_final.mp4"
Mover "$V\Tatiane Nascimento.mp4"   "$V\Tatiane\YouTube\Tatiane Nascimento.mp4"
Mover "$V\tatiane_yt.mp4"           "$V\Tatiane\YouTube\_versões antigas\tatiane_yt.mp4"
Mover "$V\tatiane_yt_1.mp4"         "$V\Tatiane\YouTube\_versões antigas\tatiane_yt_1.mp4"
Lixeira "$V\tatiane_yt_1.24212.57412.m4v"
Mover "$V\Tatiane_reels"            "$V\Tatiane\Reels"
Mover "$VV\Tatiane"                 "$V\Tatiane\Arte"
# Beatriz
Mover "$V\Beatriz_YT.mp4"           "$V\Beatriz\YouTube\Beatriz_YT.mp4"
Mover "$VV\02. Beatriz"             "$V\Beatriz"
Mover "$V\Beatryz Maynart"          "$V\Beatriz\Arte\Beatryz Maynart"
Mover "${C}Beatriz_Reels"           "$V\Beatriz\Reels"
# Mayara
Mover "$VV\01. Mayara"              "$V\Mayara"
Mover "$V\Reels_mayara"             "$V\Mayara\Reels"
# Estelamar
Mover "$V\estelamar_yt.mp4"         "$V\Estelamar\YouTube\estelamar_yt.mp4"
Mover "$V\Estelamar\Estelamar.mp4"  "$V\Estelamar\YouTube\Estelamar.mp4"
Mover "$V\Reels_Estelamar"          "$V\Estelamar\Reels"
# Maria Cleidilene
Mover "$V\Maria Cleidilene\MARIA CLEIDILEINE.mp4" "$V\Maria Cleidilene\YouTube\MARIA CLEIDILEINE.mp4"
Mover "$V\final_maria.mov"          "$V\Maria Cleidilene\YouTube\final_maria.mov"
Mover "$CFr\maria cleidilene_YT.mp4" "$V\Maria Cleidilene\YouTube\maria cleidilene_YT.mp4"
# Nailde
Mover "${C}Nailde_reels\Nailde_yt.mp4" "$V\Nailde\YouTube\Nailde_yt.mp4"
Mover "$CFr\Nailde.mp4"             "$V\Nailde\YouTube\Nailde.mp4"
Mover "${C}Nailde_reels"            "$V\Nailde\Reels"
# Cassia e Cris (estavam em Marca Página\05. Frame)
Mover "$CFr\Cassia_YT.mp4"          "$V\Cassia\YouTube\Cassia_YT.mp4"
Mover "$CFr\Cris_yt.mp4"            "$V\Cris\YouTube\Cris_yt.mp4"
# Simoni, modelo, montagens e avulsos
Mover "$VV\07. Simoni"              "$V\Simoni"
Mover "$VV\00. MODELO"              "$V\00. Modelo"
Mover "$V\03. Frame_Vivi"           "$V\Frame Vivi (montagens)"
Mover "$V\Cópia de Thumb - Vivi.jpg"     "$V\00. Thumbs\Cópia de Thumb - Vivi.jpg"
Mover "$V\Cópia de Thumb - Vivi (1).jpg" "$V\00. Thumbs\Cópia de Thumb - Vivi (1).jpg"
Mover "$V\IMG_1757.MOV"             "$V\90. A triar\IMG_1757.MOV"
Mover "$V\IMG_1758.MOV"             "$V\90. A triar\IMG_1758.MOV"
Mover-Resto $VV "$V\90. A triar\00. Vídeos (resto)"

Etapa '3. Cinza: Hypper, Freelas, Ale Busato e pastas vazias'
Mover "${C}03. Hypper"              $HY
Mover "${C}05. Freelas"             "${C}02. Freelas"
Mover "${C}Curso_Advocacia 6D"      "$ALE\Curso (vídeos finais)"
Remover-SeVazia "${C}Varandagem"
Remover-SeVazia "${C}Nova pasta"

# ----------------------------- CINZA -> SEAGATE ----------------------------
Etapa '4. Marca Página do Cinza -> Seagate (cópia conferida)'
Copiar-Entre-HDs $CMP $EMP

# ----------------------------- SEAGATE (interno) ---------------------------
Etapa '5. Seagate: junta as 4 pastas do Marca Página + o que veio do Cinza'
Mover "$SMP0\02. Reels"             "$MP\02. Reels"
Mover "$SMP0\Ads e reels Janeiro"   "$MP\02. Reels\Ads e reels Janeiro"
Mover "$SMP\Reels"                  "$MP\02. Reels\Reels antigos"
Mover "$SMP\Bruno - Abrilmaio"      "$MP\01. YouTube\Bruno - Abril-Maio 2024"
Mover "$SMP\Youtube"                "$MP\01. YouTube\YouTube antigo"
Mover "$SMP0\01. Projetos"          "$MP\00. Projetos Premiere"
Mover "$SMP0\CopyPasta"             "$MP\00. Projetos Premiere\CopyPasta"
Mover "$SMP0\Leva_03.20 Masks"      "$MP\00. Projetos Premiere\Leva_03.20 Masks"
if (Test-Path -LiteralPath $SMP0) {
    foreach ($f in Get-ChildItem -LiteralPath $SMP0 -File -Filter '*.prproj' -Force) {
        Mover $f.FullName "$MP\00. Projetos Premiere\$($f.Name)"
    }
}
Mover "$SMP0\ID_Visual"             "$MP\04. ID Visual"
Mover "$SMP0\_Assets"               "$MP\04. ID Visual\_Assets"
Mover "$SMP0\03. Carrossel"         "$MP\05. Carrossel"
Mover "$SMP0\Arquivo"               "$MP\99. Arquivo\Arquivo (00. Marca Página)"
Mover "$SMP\Arquivo"                "$MP\99. Arquivo\Arquivo (Seagate)"
Mover "$SMP\Marca Pagina"           "$MP\90. A triar\Marca Pagina"
Mover "$SMP\Marca Pag"              "$MP\90. A triar\Marca Pag"
Mover-Resto $SMP0                   "$MP\90. A triar\Resto de 00. Marca Página"
Mover-Resto $SMP                    "$MP\90. A triar\Soltos (Seagate)"

Mover "$EMP\01. Youtube"            "$MP\01. YouTube"
Mover "$EMP\00. Solo Levelling - EPS" "$MP\01. YouTube\Solo Leveling - EPS"
Mover "$EMP\05. Frame"              "$MP\01. YouTube\Frame"
Mover "$EMP\CCXP25"                 "$MP\03. Eventos\CCXP25"
Mover "$EMP\02. Projetos"           "$MP\00. Projetos Premiere\Projetos (HD Cinza)"
Mover "$EMP\01. Thumbs"             "$MP\06. Thumbs"
Mover "$EMP\03. ID"                 "$MP\04. ID Visual\ID (HD Cinza)"
Mover "$EMP\00. Vídeos"             "$MP\90. A triar\00. Vídeos (HD Cinza)"
Mover "$EMP\04. News"               "$MP\90. A triar\News"
Mover-Resto $EMP                    "$MP\90. A triar\Soltos (HD Cinza)"

# ----------------------------- SEAGATE -> CINZA ----------------------------
Etapa '6. Clientes do Seagate -> Cinza (cópias conferidas)'
Copiar-Entre-HDs "$SP\00. Hypper"   "$HY\_entrada Seagate"
Mover "$HY\_entrada Seagate\03. Oh creamy" "$HY\03. Oh Creamy"
Mover "$HY\_entrada Seagate\Mr. Cheney"    "$HY\04. Mr. Cheney"
Mover "$HY\_entrada Seagate\99. NFs"       "$HY\99. NFs"
Mover-Resto "$HY\_entrada Seagate"         "$HY\90. Soltos (Seagate)"

Copiar-Entre-HDs "$SP\Historia de divorcio" "$V\_entrada Seagate"
Mover "$V\_entrada Seagate\01. Vídeo patrocinio" "$V\Patrocínio"
Mover "$V\_entrada Seagate\04. 4 nov"            "$V\Karine Moraes"
Mover-Resto "$V\_entrada Seagate"                "$V\90. A triar\Soltos (Seagate)"

Copiar-Entre-HDs "$SD\Ale Busato"       "$ALE\Gravações Zoom"
Copiar-Entre-HDs "$SD\Yana"             "${C}01. Clientes\Yana"
Copiar-Entre-HDs "$SD\Luiz"             "${C}01. Clientes\Luiz\Ghost"
Copiar-Entre-HDs "$SD\Cortes_Luiz"      "${C}01. Clientes\Luiz\Cortes"
Copiar-Entre-HDs "$SD\Jovem Aventura"   "${C}01. Clientes\Jovem Aventura"
Copiar-Entre-HDs "$SD\Lenise"           "${C}02. Freelas\Lenise"
Copiar-Entre-HDs "$SD\universe"         "${C}02. Freelas\Universe"
Copiar-Entre-HDs "$SD\Freelas diversos" "${C}02. Freelas\Clube R1"

# ----------------------------- SEAGATE (pessoal e resto) -------------------
Etapa '7. Seagate: Pessoal, Backups, Recursos e restos do Windows'
Mover "$SD\Tic Pic"                 "${S}04. Pessoal\Tic Pic"
Mover "$SD\Canal Ia"                "${S}04. Pessoal\Canal IA"
Mover "$SD\Pessoal"                 "${S}04. Pessoal"
Mover "$SD\Backup"                  "${S}04. Pessoal\Backup 2022"
Mover "$SD\Edição\Brocolis Fízika.ai" "${S}04. Pessoal\Backup 2022\Brocolis Fízika.ai"
Lixeira "$SD\Edição"                # copiada para o Mac e conferida byte a byte em 24/10/2026
Mover "$SD\OL_Transition_11[1]"     "${S}03. Recursos de Edição\OL_Transition_11"
Mover "${S}Backup_Helen"            "${S}05. Backups de Computador\Helen"
Mover "${S}found.000"               "${S}99. Recuperados\found.000"
Mover "${S}found.001"               "${S}99. Recuperados\found.001"
Lixeira "$SD\desktop.ini"
Lixeira ("$SD\" + '~$ do list.docx')
Lixeira ("$SD\" + '~$mposition Juliano.docx')
Remover-SeVazia "$SD\Backup 2024"
Remover-SeVazia "$SD\Adobe"
Remover-SeVazia "${S}Program Files"
Remover-SeVazia "${S}WindowsApps"
Mover-Resto $SP                     "${S}90. A triar\00_Projetos Ativos (resto)"
Mover-Resto $SD                     "${S}90. A triar\Desktop (resto)"

# ----------------------------- Resumo --------------------------------------
Etapa 'Resumo'
Log ("Mover: {0} | Copiar entre HDs: {1} | Para apagar: {2} | Pulados: {3} | Conflitos: {4} | Erros: {5}" -f `
    $script:Conta.Mover, $script:Conta.Copiar, $script:Conta.Lixeira, $script:Conta.Pulado, $script:Conta.Conflito, $script:Conta.Erro)
foreach ($u in $script:BytesPara.Keys) {
    $livre = (Get-PSDrive -Name $u.Substring(0, 1)).Free
    $nome = if ($u -eq $C) { 'Cinza' } else { 'Seagate' }
    $ok = if ($livre -gt $script:BytesPara[$u]) { 'OK' } else { 'NÃO CABE!' }
    Log "  Chega no $nome ($u): $(GB $script:BytesPara[$u]) | livre hoje: $(GB $livre) | $ok"
}

if ($Executar) {
    $indice = @{
        $C = "HD_EXTERNO_CINZA: clientes (Vivi, Hypper, Ale Busato, Yana, Luiz, Jovem Aventura) e Freelas.`r`nNo Seagate: Marca Página, Pessoal e Backups de computador."
        $S = "Seagate Expansion Drive: Marca Página, Pessoal e Backups de computador.`r`nNo HD Cinza: os outros clientes (Vivi, Hypper, Ale Busato, Yana, Luiz, Jovem Aventura) e Freelas."
    }
    foreach ($r in @($C, $S)) {
        $linhas = @($indice[$r], '', "Organizado em $(Get-Date -Format 'dd/MM/yyyy').", '')
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force | Where-Object { $_.Name -notmatch '^\$|System Volume Information' } | Sort-Object Name) {
            $linhas += $d.Name
            foreach ($s in Get-ChildItem -LiteralPath $d.FullName -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name) { $linhas += "    $($s.Name)" }
        }
        Set-Content -LiteralPath (Join-Path $r '00. LEIA-ME.txt') -Value $linhas -Encoding UTF8
    }
    Log 'LEIA-ME criado na raiz dos dois HDs.'
    Log 'Revise "_Para apagar" em cada HD e esvazie quando estiver tranquilo.'
}
Log "Log salvo em $LogArq"
