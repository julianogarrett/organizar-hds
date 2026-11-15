<#
  PC_Classificar.ps1 - classifica o trabalho do PC Windows (C: e D:) e gera pc_plano.csv. Só leitura.
  Colunas: origem;destino;acao;tipo;cliente;obs;bytes
  acao:
    COPIAR        copia pro HD, confere, original -> <disco>:\_Para apagar\_Ja copiado para os HDs\...
    COPIAR_MANTER copia pro HD (pessoal), original fica
    JA_NO_HD      já existe arquivo igual (tamanho+ext) nos HDs -> original para _Para apagar\_Ja estava nos HDs\...
    DUPLICATA     cópia de outro arquivo do PC que vai pro HD -> _Para apagar\_Duplicatas\...
    REVISAR       fica no PC: <disco>:\90. A revisar\...
    APAGAR        cache/lixo: <disco>:\_Para apagar\...
    MAC           cópia para D:\05. Para o Mac\...
#>
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$HDE = 'E:\'; $HDS = 'F:\'; $MAC = 'D:\05. Para o Mac'
$U = 'C:\Users\julia'

function SemAcento([string]$s) {
    $n = $s.Normalize([Text.NormalizationForm]::FormD); $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) } }
    $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}
function Limpar([string]$s) {
    $s = SemAcento $s
    $s = $s -replace '[^A-Za-z0-9 \-\.]', ' ' -replace '\s+', ' '
    $s = $s.Trim(' .-')
    if ($s.Length -gt 60) { $s = $s.Substring(0, 60).Trim() }
    if ($s.Length -gt 0) { $s = $s.Substring(0, 1).ToUpper() + $s.Substring(1) }
    $s
}
function Titulo([string]$nome, [string]$cli) {
    $t = [IO.Path]::GetFileNameWithoutExtension($nome)
    $t = $t -replace '^\d{2}-\d{2}(-\d{2})?_', '' -replace '^\d{2}-\d{2}_', ''
    $t = $t -replace '(?i)[ _\-]?(v\d+|final|ofc|oficial)(?=$|[ _\-])', ''
    $t = $t -replace '(?i)^(bruno|emy|felipe|andi|vivi|mayara|hb|ryan)[ _]', ''
    $t = Limpar ($t -replace '_', ' ')
    if (-not $t) { $t = 'Sem titulo' }
    $t
}
function Chave([string]$nome) {
    $t = (SemAcento ([IO.Path]::GetFileNameWithoutExtension($nome))).ToLower()
    $t = $t -replace '\s*\(\d+\)', '' -replace '[ _\-]v\d+', '' -replace '[ _\-]?final', ''
    $t -replace '[^a-z0-9]', ''
}
function NumVersao([string]$nome) {
    $s = [IO.Path]::GetFileNameWithoutExtension($nome)
    if ($s -match '(?i)final') { return 1000 }
    if ($s -match '(?i)[ _\-]v(\d+)') { return [int]$matches[1] }
    if ($s -match '_(\d)$') { return [int]$matches[1] }
    return 0
}
function SemDrive([string]$p) { $p.Substring(3) }

# ---------------------------------------------------------------- índice dos HDs (tamanho+ext, > 5 MB)
Write-Host 'Indexando HDs...'
$noHD = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($hd in $HDE, $HDS) {
    Get-ChildItem $hd -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 5MB } | ForEach-Object { [void]$noHD.Add("$($_.Length)|$($_.Extension.ToLower())") }
}

# ---------------------------------------------------------------- clientes
# Ativos (mexidos de jun/2026 pra cá): assets deles também vão pro Mac
$ativos = 'Vivi', 'Marca Pagina', 'Felipe Rodrigues', 'Andi', 'Emy Oliveira'
function NovoCli($nome, $grupo, $hd) { @{ Cliente = $nome; Grupo = $grupo; HD = $hd } }
$porCaminho = @(
    @('D:\01. Trabalho\01. Vivi', (NovoCli 'Vivi' 'Clientes' $HDE)),
    @('D:\01. Trabalho\02. Bruno', (NovoCli 'Marca Pagina' 'Clientes' $HDS)),
    @('D:\01. Trabalho\__ANALISAR\00. Marca Página', (NovoCli 'Marca Pagina' 'Clientes' $HDS)),
    @('D:\01. Trabalho\03. Felipe Rodrigues', (NovoCli 'Felipe Rodrigues' 'Clientes' $HDE)),
    @('D:\01. Trabalho\04. Andi', (NovoCli 'Andi' 'Clientes' $HDS)),
    @('D:\01. Trabalho\05. Emy Oliveira', (NovoCli 'Emy Oliveira' 'Clientes' $HDS)),
    @('D:\01. Trabalho\98. Freelas\Aulas HB', (NovoCli 'Hypper' 'Clientes' $HDE)),
    @('D:\01. Trabalho\98. Freelas\HB_AULAS EXTRAS ABRIL', (NovoCli 'Hypper' 'Clientes' $HDE)),
    @('D:\01. Trabalho\98. Freelas\hb_leva diversas', (NovoCli 'Hypper' 'Clientes' $HDE)),
    @('D:\01. Trabalho\98. Freelas\podcasts HB', (NovoCli 'Hypper' 'Clientes' $HDE)),
    @('D:\01. Trabalho\98. Freelas\PEDRO', (NovoCli 'Pedro' 'Freelas' $HDS)),
    @('D:\01. Trabalho\98. Freelas\SABBIA', (NovoCli 'Sabbia' 'Freelas' $HDS)),
    @('D:\01. Trabalho\98. Freelas\Varandagem', (NovoCli 'Varandagem' 'Freelas' $HDS)),
    @('D:\01. Trabalho\98. Freelas\Fluidita Logo', (NovoCli 'Fluidita' 'Freelas' $HDS)),
    @('D:\01. Trabalho\ewfa', (NovoCli 'EWFA' 'Freelas' $HDS)),
    @('D:\01. Trabalho\__ANALISAR\02. Joao', (NovoCli 'Joao' 'Freelas' $HDS)),
    @('D:\01. Trabalho\__ANALISAR\03. Ana Paula', (NovoCli 'Ana Paula' 'Freelas' $HDS)),
    @('D:\01. Trabalho\Site zaira', (NovoCli 'Zaira' 'Freelas' $HDS)),
    @('D:\01. Trabalho\99. deNoise', (NovoCli 'deNoise' 'deNoise' $HDS)),
    @("$U\Desktop\NGCASH", (NovoCli 'NG Cash' 'Freelas' $HDS)),
    @("$U\Desktop\vlog 02 - julho", (NovoCli 'Felipe Rodrigues' 'Clientes' $HDE)),
    @('D:\vlog 04 julho', (NovoCli 'Felipe Rodrigues' 'Clientes' $HDE)),
    @("$U\Desktop\Tudo", (NovoCli 'Hypper' 'Clientes' $HDE))
)
$porNome = @(
    @('(?i)^hb[_ ]|hbpodcast|mr cheney|chicken town|_uni_|^uni_|aulas hb|^cremoso', (NovoCli 'Hypper' 'Clientes' $HDE)),
    @('(?i)denoise|^nfs|reconter|^proposta|contrato social|onboarding clientes|or.amento anual|controle_financeiro|^sales_|^students_|^broadcasts-|^total_subscribers|^fatura|termo_de_transfer|calibase', (NovoCli 'deNoise' 'deNoise' $HDS)),
    @('(?i)^bruno|^bn_|marca p.gina|^review_|chainsmoker|brand new day|react.?teaser|trailler pc|estande jbc|cosplay|dia comigo no af|_af_|mercado livre|8 do 8|^stories|chainsaw man_v|^publi|primeira tentativa da publicidade|^teste_publi|great pretender|devorador|jiraya|viktor|clube do otaku', (NovoCli 'Marca Pagina' 'Clientes' $HDS)),
    @('(?i)^emy|calistenia|flex.o|agachamento|canoinha|pistol|remada|puxada|l-sit|^dip |handstand|stiff sandbag|corrigindo|sem equipamentos', (NovoCli 'Emy Oliveira' 'Clientes' $HDS)),
    @('(?i)^felipe|vlog|ryan|outlier|creator economy|manualyt|manual do youtube|manual_youtube|1 passo de transformar|cheff otto|^aula_|melhor horario|teste_pensamentos|^vsl|algoritmo|cybele|^26-07-14_|desenhos dc|the office brasileiro|buddy dadies', (NovoCli 'Felipe Rodrigues' 'Clientes' $HDE)),
    @('(?i)^andi|contos nao sao|^ba_|ali ?bab|rapunzel|cinderella|tangled|sleeping|prince philip|gothel|disney|^aulao', (NovoCli 'Andi' 'Clientes' $HDS)),
    @('(?i)^mayara|vivi|separ|hist.rias? de div|viol.ncia patrimonial|^katia|^rubi_|^monica_|ele exigia|^dina|marizete|sahmia|^marcela|luciana|^thumbs-|qr ?code_membros|^ana paula|^camila|^kellen|^simone|^tamires|^claudiane|^lais|^maria|^patricia|^rafaela|^regia|^rosiclea|^elaina|^nathalia|^joice|^jo.o pedro lisboa|^debora|^d.bora|^img_1364|continue a nadar|^audio andre|^aves - ', (NovoCli 'Vivi' 'Clientes' $HDE))
)
function Get-Cliente([string]$p, [string]$n) {
    foreach ($r in $porCaminho) { if ($p.StartsWith($r[0] + '\', [StringComparison]::OrdinalIgnoreCase)) { return @{ C = $r[1]; Raiz = $r[0] } } }
    foreach ($r in $porNome) { if ($n -match $r[0]) { return @{ C = $r[1]; Raiz = [IO.Path]::GetDirectoryName($p) } } }
    $null
}
function RaizCliente($c) {
    switch ($c.Grupo) { 'Clientes' { "$($c.HD)01. Clientes\$($c.Cliente)" } 'Freelas' { "$($c.HD)02. Freelas\$($c.Cliente)" } 'deNoise' { "$($HDS)04. Pessoal\deNoise" } }
}

# ---------------------------------------------------------------- padrões
$reCache = '(?i)\\(Adobe Premiere Pro (Audio|Video) Previews|Adobe Premiere Pro Auto-Save|After Effects Auto-Save|Media Cache( Files)?|CacheClip|\.gallery|Proxies)\\|(?i)_proxy\.'
$reLixoNome = '(?i)^(desktop\.ini|thumbs\.db|~\$.*|.*\.tmp|.*\.crdownload|.*\.lnk)$'
$reProjeto = '(?i)\.(prproj|aep|aepx|drp|prin|drt|psd|ai|aet)$'
$reVideo = '(?i)\.(mp4|mov|mkv|m4v|mxf|avi|webm|mts)$'
$reAudio = '(?i)\.(mp3|wav|m4a|aac|ogg|flac|aif|aiff)$'
$reBaixado = '(?i)ytdown|youtube\)|\(\d+p, h264|snaptik|ssstik|saveclip|klickpin|pindown|^\d{6,}[-_]|^\d{4,}-\d+\.mp4$|^[0-9a-f]{32}\.|^[0-9a-f]{8}-[0-9a-f]{4}-|\[judas\]|^from klickpin|_202\d{9}\.mp4$|…_20\d{10}'
$rePastaBruto = '(?i)\\(arquivos brutos|brutos?|raw|footage|grava..o[^\\]*|arquivos de m.dia|para adicionar|para sobreposi..o|drone|[^\\]*drone[^\\]*|festa junina[^\\]*|mic\d[^\\]*|brolls?|b-?roll|material|captured and generated|\[[a-z]+\][^\\]*|omc|\d{2}-\d{2} grava[^\\]*|aula de limpeza[^\\]*)\\'
$reNomeBruto = '(?i)^(c\d{4}|dsc|dscf|mvi_|dji_|gx\d|gopr|pxl_|img_|copy_|\d{4}( \(\d\))?\.|\d{4}-\d\d-\d\d \d\d-\d\d-\d\d|abertura \d+ - dscf|primeira tentativa da publicidade dscf|nova grava)'
$reTrilha = '(?i)^(artlist|fly sound|ni sound|soundholder|soundkrampf)|^[^_]{2,40} - [^_]{2,80}\.(mp3|wav|aac)$'
$reMacRecurso = '(?i)\.(zxp|prfpset|mogrt|kys|cube|look|ttf|otf)$|plugin textos virais|grift'

$extImg = '(?i)\.(jpe?g|png|webp|gif|svg|ico|bmp|tiff?|heic)$'
$extDoc = '(?i)\.(pdf|docx?|xlsx?|csv|pptx?|html?|enc|kys|txt)$'

# ---------------------------------------------------------------- arquivos de origem
Write-Host 'Lendo arquivos do PC...'
$todos = New-Object System.Collections.ArrayList
function Add-Files($path, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $fs = if ($Recurse) { Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue } else { Get-ChildItem -LiteralPath $path -File -Force -ErrorAction SilentlyContinue }
    foreach ($f in $fs) { [void]$todos.Add($f) }
}
Add-Files 'D:\01. Trabalho' -Recurse
Add-Files 'D:\vlog 04 julho' -Recurse
Add-Files 'D:\Design sem nome' -Recurse
Add-Files 'D:\'
Add-Files "$U\Desktop" -Recurse
Add-Files "$U\Downloads" -Recurse
Add-Files "$U\Documents"
Add-Files "$U\Videos" -Recurse
Add-Files "$U\Pictures" -Recurse
Add-Files 'D:\02. Pessoal' -Recurse

$plano = New-Object System.Collections.ArrayList
function Linha($o, $d, $a, $t, $c, $obs, $b) { [void]$plano.Add([pscustomobject]@{ origem = $o; destino = $d; acao = $a; tipo = $t; cliente = $c; obs = $obs; bytes = $b }) }
function Revisar($f, $t, $c, $obs) { Linha $f.FullName ($f.FullName.Substring(0, 3) + '90. A revisar\' + (SemDrive $f.FullName)) 'REVISAR' $t $c $obs $f.Length }
function Apagar($f, $t, $obs) { Linha $f.FullName ($f.FullName.Substring(0, 3) + '_Para apagar\' + (SemDrive $f.FullName)) 'APAGAR' $t '' $obs $f.Length }
function Mac($f, $sub) { Linha $f.FullName (Join-Path $MAC (Join-Path $sub $f.Name)) 'MAC' 'para o mac' '' '' $f.Length }

$exportCand = New-Object System.Collections.ArrayList   # @{F; C; Raiz}
$pessoal = 'D:\02. Pessoal', "$U\Pictures", "$U\Videos"
$fica = @('D:\02. Pessoal\00. Jogos', 'D:\02. Pessoal\Crusader Kings II 3.3.0 DLC Files', "$U\Downloads\Black-Jacket-SteamRIP.com")
$naoMexer = '(?i)^(pagefile\.sys|dumpstack\.log\.tmp|swapfile\.sys|hiberfil\.sys)$'

foreach ($f in $todos) {
    $p = $f.FullName; $n = $f.Name
    if ($p -like 'D:\organizar-hds\*' -or $n -match $naoMexer) { continue }
    if ($fica | Where-Object { $p.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }) { continue }
    if ($n -match '\.mkv$' -and $n -match '\[judas\]') { continue }   # anime baixado: fica (pessoal)
    # atalhos e arquivos de sistema soltos no Desktop: ficam
    if ([IO.Path]::GetDirectoryName($p) -ieq "$U\Desktop" -and $n -match '(?i)\.(lnk|url)$|^desktop\.ini$') { continue }

    # cache e lixo
    if ($p -match $reCache -or $n -match $reLixoNome) { Apagar $f 'cache' ''; continue }

    # pessoal: copia e mantém
    $pes = $pessoal | Where-Object { $p.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($pes) {
        if ($n -match '(?i)contrato - historias de divorcio') { } # cai na regra de cliente abaixo
        else {
            $rel = $p.Substring(3)
            Linha $p "$($HDS)04. Pessoal\PC Windows\$rel" 'COPIAR_MANTER' 'pessoal' '' '' $f.Length; continue
        }
    }

    # recursos de edição
    if ($p.StartsWith('D:\01. Trabalho\00. Assets edicao\', [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $p.Substring('D:\01. Trabalho\00. Assets edicao\'.Length)
        Linha $p "$($HDS)03. Recursos de Edicao\Assets edicao PC\$rel" 'COPIAR' 'recurso' '' '' $f.Length
        Linha $p (Join-Path "$MAC\Recursos de Edicao" $rel) 'MAC' 'para o mac' '' 'recurso de edicao' $f.Length
        continue
    }
    if ($n -match $reMacRecurso -or $p -match '\\grift-geometric-typeface\\') {
        Linha $p "$($HDS)03. Recursos de Edicao\Plugins e presets PC\$n" 'COPIAR' 'recurso' '' '' $f.Length
        Mac $f 'Recursos de Edicao\Plugins presets e fontes'; continue
    }
    if ($n -match $reAudio -and $n -match $reTrilha -and $n -notmatch 'esv2') {
        Linha $p "$($HDS)03. Recursos de Edicao\Trilhas e SFX PC\$n" 'COPIAR' 'trilha' '' '' $f.Length
        Mac $f 'Trilhas e SFX'; continue
    }

    $ci = Get-Cliente $p $n
    $c = if ($ci) { $ci.C } else { $null }
    $cn = if ($c) { $c.Cliente } else { '' }

    if ($n -match '(?i)\.(exe|msi|winmd)$') { Revisar $f 'instalador' $cn ''; continue }
    if ($n -match '(?i)\.(zip|rar|7z)$') { Revisar $f 'zip' $cn ''; continue }

    if ($n -match $reVideo) {
        if ($n -match $reBaixado -or $p -match '(?i)\\brolls?\\') { Revisar $f 'baixado' $cn ''; continue }
        if ($n -match '(?i)esv2') { Revisar $f 'intermediario' $cn 'enhance speech'; continue }
        $stem = [IO.Path]::GetFileNameWithoutExtension($n)
        $caps = ($stem -cnotmatch '[a-zà-ú]') -and ($stem -match '[A-Z]{3}') -and ($stem -notmatch '(?i)_yt|final|headline|^(VSL|AD|BN|HB)') -and ($cn -in 'Vivi','')
        if ($p -match $rePastaBruto -or $n -match $reNomeBruto -or $n -match '(?i)\.mkv$' -or ($n -match '(?i)\.mov$' -and $n -notmatch '(?i)final|export') -or $caps) { Revisar $f 'bruto' $cn ''; continue }
        if (-not $c) { Revisar $f 'video sem dono' '' 'REVISAR CLIENTE'; continue }
        [void]$exportCand.Add(@{ F = $f; C = $c; Raiz = $ci.Raiz }); continue
    }
    if ($n -match $reAudio) {
        if ($c -and $p -match '(?i)\\0?0\. assets\\') { Linha $p ((RaizCliente $c) + '\Assets\' + $p.Substring($ci.Raiz.Length + 1)) 'COPIAR' 'asset' $cn '' $f.Length; continue }
        Revisar $f 'audio' $cn ''; continue
    }
    if (-not $c) {
        Revisar $f 'sem dono' '' ''; continue
    }
    if ($n -match '(?i)\.txt$') { Revisar $f 'transcricao' $cn ''; continue }
    if ($n -match $reProjeto) {
        [void]$exportCand.Add(@{ F = $f; C = $c; Raiz = $ci.Raiz; Projeto = $true }); continue
    }
    # imagens, docs e o resto do cliente -> Assets
    $rel = $p.Substring($ci.Raiz.Length + 1)
    $tipo = if ($c.Grupo -eq 'deNoise') { 'documento' } else { 'asset' }
    $dest = if ($c.Grupo -eq 'deNoise' -and $ci.Raiz -notlike 'D:\01. Trabalho\99. deNoise') { (RaizCliente $c) + "\Documentos\$rel" } else { (RaizCliente $c) + "\Assets\$rel" }
    if ($c.Grupo -eq 'deNoise' -and $ci.Raiz -like 'D:\01. Trabalho\99. deNoise') { $dest = (RaizCliente $c) + "\$rel" }
    Linha $p $dest 'COPIAR' $tipo $cn '' $f.Length
    if ($c.Grupo -eq 'deNoise' -and $n -match $extDoc) { Mac $f 'deNoise Documentos' }
    elseif ($ativos -contains $cn -and $f.Length -lt 500MB) { Linha $p (Join-Path "$MAC\Clientes\$cn" $rel) 'MAC' 'para o mac' $cn 'asset de cliente ativo' $f.Length }
}

# ---------------------------------------------------------------- exports: versões, grupos, nomes
Write-Host 'Montando conteudos...'
$exports = $exportCand | Where-Object { -not $_.Projeto }
$projetos = $exportCand | Where-Object { $_.Projeto }

# versões no mesmo diretório
$vencedores = New-Object System.Collections.ArrayList
foreach ($g in ($exports | Group-Object { $_.F.DirectoryName + '|' + (Chave $_.F.Name) })) {
    $itens = @($g.Group)
    # junta "x_1" com "x"
    if ($itens.Count -eq 1) { [void]$vencedores.Add($itens[0]); continue }
    $ord = $itens | Sort-Object @{ e = { NumVersao $_.F.Name }; Descending = $true }, @{ e = { $_.F.LastWriteTime }; Descending = $true }
    [void]$vencedores.Add($ord[0])
    foreach ($o in ($ord | Select-Object -Skip 1)) { Revisar $o.F 'versao antiga' $o.C.Cliente "final escolhida: $($ord[0].F.Name)" }
}
# "x_1.mp4" ao lado de "x.mp4"
$porDir = $vencedores | Group-Object { $_.F.DirectoryName }
$final = New-Object System.Collections.ArrayList
foreach ($d in $porDir) {
    $chaves = @{}; foreach ($i in $d.Group) { $chaves[(Chave $i.F.Name)] = $i }
    foreach ($i in $d.Group) {
        $k = Chave $i.F.Name
        $base1 = if ($i.F.BaseName -match '_\d$' -and $k -match '^(.+?)\d$') { $matches[1] } else { $null }
        if ($base1 -and $chaves.ContainsKey($base1) -and -not $chaves[$base1].Descartado -and $chaves[$base1] -ne $i) {
            $outro = $chaves[$base1]
            Revisar $outro.F 'versao antiga' $outro.C.Cliente "final escolhida: $($i.F.Name)"
            $outro.Descartado = $true
        }
    }
    foreach ($i in $d.Group) { if (-not $i.Descartado) { [void]$final.Add($i) } }
}
$final = @($final | Where-Object { -not $_.Descartado })

# duplicatas pelo PC (mesmo nome + tamanho): fica o que está dentro da pasta do cliente
$vistos = @{}
$final2 = New-Object System.Collections.ArrayList
foreach ($i in ($final | Sort-Object { $_.Raiz.Length } -Descending)) {
    $k = "$($i.F.Name)|$($i.F.Length)"
    if ($vistos.ContainsKey($k)) { Linha $i.F.FullName ($i.F.FullName.Substring(0, 3) + '_Para apagar\_Duplicatas\' + (SemDrive $i.F.FullName)) 'DUPLICATA' 'duplicata' $i.C.Cliente "igual a $($vistos[$k])" $i.F.Length; continue }
    $vistos[$k] = $i.F.FullName; [void]$final2.Add($i)
}

# grupo = pasta nomeada (não genérica) dentro do cliente, 2..40 exports, até 45 dias
$reGenerica = '(?i)^(\d+\.\s*)?(e?xports?|final|finais|renders?|v.deos?|videos?|20\d\d|\d{2}\.\s*(janeiro|fevereiro|mar.o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)|janeiro|fevereiro|mar.o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|alteracoes.*|\d{4}_?|.*hist.rias de div.rcio|superacoes|\d+\. mayara)$'
function PastaGrupo($i) {
    $d = $i.F.DirectoryName
    while ($d -and $d.Length -gt $i.Raiz.Length) {
        $leaf = Split-Path $d -Leaf
        if ($leaf -notmatch $reGenerica) { return $d }
        $d = Split-Path $d -Parent
    }
    $null
}
foreach ($i in $final2) { $i.Grupo = PastaGrupo $i }
$grupos = @{}
foreach ($g in ($final2 | Where-Object { $_.Grupo } | Group-Object { $_.Grupo })) {
    $ds = $g.Group | ForEach-Object { $_.F.LastWriteTime } | Measure-Object -Minimum -Maximum
    if ($g.Count -ge 2 -and $g.Count -le 120 -and ($ds.Maximum - $ds.Minimum).TotalDays -le 45) { $grupos[$g.Name] = $ds.Minimum }
}

$usados = @{}
function Unico([string]$dest) {
    $d = $dest; $k = 2
    while ($usados.ContainsKey($d.ToLower())) { $d = [IO.Path]::Combine([IO.Path]::GetDirectoryName($dest), [IO.Path]::GetFileNameWithoutExtension($dest) + " $k" + [IO.Path]::GetExtension($dest)); $k++ }
    $usados[$d.ToLower()] = 1; $d
}
$pastaConteudo = @{}   # grupo -> pasta destino
foreach ($i in $final2) {
    $f = $i.F; $c = $i.C; $cn = $c.Cliente; $raiz = RaizCliente $c
    $tit = Titulo $f.Name $cn
    if ($noHD.Contains("$($f.Length)|$($f.Extension.ToLower())")) {
        Linha $f.FullName ($f.FullName.Substring(0, 3) + '_Para apagar\_Ja estava nos HDs\' + (SemDrive $f.FullName)) 'JA_NO_HD' 'export' $cn 'arquivo igual (tamanho) ja esta num HD' $f.Length; continue
    }
    if ($i.Grupo -and $grupos.ContainsKey($i.Grupo)) {
        if (-not $pastaConteudo.ContainsKey($i.Grupo)) {
            $dt = $grupos[$i.Grupo]; $gt = Limpar ((Split-Path $i.Grupo -Leaf) -replace '^\d+\.\s*', '' -replace '[_\[\]]', ' ')
            $pastaConteudo[$i.Grupo] = "$raiz\Conteudos\$($dt.ToString('yyyy'))\$($dt.ToString('yyyy-MM'))_$gt"
        }
        $pasta = $pastaConteudo[$i.Grupo]
    } else {
        $pasta = "$raiz\Conteudos\$($f.LastWriteTime.ToString('yyyy'))\$($f.LastWriteTime.ToString('yyyy-MM'))_$tit"
        if ($i.F.DirectoryName -ne $i.Raiz) { $pastaConteudo['solo|' + $f.FullName] = $pasta }
    }
    $obs = if ($tit -eq 'Sem titulo' -or $tit.Length -lt 4) { 'REVISAR TITULO' } else { '' }
    $dest = Unico "$pasta\$($f.LastWriteTime.ToString('yyyy-MM-dd'))_$($cn)_$tit$($f.Extension.ToLower())"
    Linha $f.FullName $dest 'COPIAR' 'export' $cn $obs $f.Length
}
# projetos: no grupo da pasta, senão "Projetos sem conteudo"
foreach ($i in $projetos) {
    $f = $i.F; $c = $i.C; $raiz = RaizCliente $c
    $g = PastaGrupo $i
    if ($g -and $pastaConteudo.ContainsKey($g)) { $dest = "$($pastaConteudo[$g])\Projeto\$($f.Name)" }
    else { $dest = "$raiz\Projetos sem conteudo\" + $f.FullName.Substring($i.Raiz.Length + 1) }
    $dest = Unico $dest
    Linha $f.FullName $dest 'COPIAR' 'projeto' $c.Cliente '' $f.Length
    if ($f.Name -match '(?i)template|modelo') { Linha $f.FullName "$MAC\Clientes\$($c.Cliente)\$($f.Name)" 'MAC' 'para o mac' $c.Cliente 'template' $f.Length }
}

$plano | Export-Csv "$base\pc_plano.csv" -Delimiter ';' -NoTypeInformation -Encoding UTF8
Write-Host "Linhas: $($plano.Count)"
$plano | Group-Object acao | ForEach-Object { '{0,-14} {1,6} arq {2,9:N1} GB' -f $_.Name, $_.Count, (($_.Group | Measure-Object bytes -Sum).Sum / 1GB) }
'--- copias por HD'
$plano | Where-Object { $_.acao -like 'COPIAR*' } | Group-Object { $_.destino.Substring(0, 1) } | ForEach-Object { '{0}: {1,9:N1} GB' -f $_.Name, (($_.Group | Measure-Object bytes -Sum).Sum / 1GB) }
'--- revisar por tipo'
$plano | Where-Object acao -eq 'REVISAR' | Group-Object tipo | ForEach-Object { '{0,-16} {1,6} arq {2,9:N1} GB' -f $_.Name, $_.Count, (($_.Group | Measure-Object bytes -Sum).Sum / 1GB) }
'--- copias por cliente'
$plano | Where-Object { $_.acao -eq 'COPIAR' } | Group-Object cliente | ForEach-Object { '{0,-18} {1,6} arq {2,9:N1} GB' -f $_.Name, $_.Count, (($_.Group | Measure-Object bytes -Sum).Sum / 1GB) }
