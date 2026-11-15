<#
  Classificar.ps1 - passo 2. Lê inventario_*.csv e gera plano.csv (só leitura nos HDs).
  Colunas: origem;destino;acao;tipo;observacao;cliente;conteudo;tamanho
  acao: MOVER (mesmo HD) | COPIAR (outro HD, via _entrada + conferência) | MOVER_PASTA | REMOVER_SE_VAZIA
#>
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
function Raiz($label) { $v = Get-Volume -FileSystemLabel $label | Where-Object DriveLetter | Select-Object -First 1; "$($v.DriveLetter):\" }
$C = Raiz 'HD_EXTERNO_CINZA'; $S = Raiz 'Seagate Expansion Drive'
$NomeHD = @{ $C = 'HD Cinza'; $S = 'Seagate' }
$inv = [Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------- utilidades
function SemAcento([string]$s) {
    $n = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) } }
    $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}
function Limpar([string]$s) {
    $s = SemAcento $s
    $s = $s -replace '[^A-Za-z0-9 \-\.]', ' '
    $s = $s -replace '\s+', ' '
    $s = $s.Trim(' .-')
    if ($s.Length -gt 0) { $s = $s.Substring(0, 1).ToUpper() + $s.Substring(1) }
    $s
}
$reMarcaFinal = '(?i)(^|[ _\-.])(v?final|finais|ofc|oficial|corrigid[oa]|aprovad[oa])([ _\-.\d]|$)'
function TituloDeArquivo([string]$nome) {
    $t = [IO.Path]::GetFileNameWithoutExtension($nome)
    $t = $t -replace '^(?i)MP_', '' -replace '^\d{2}-\d{2}_', ''
    $t = $t -replace '(?i)[ _\-](v?final|ofc|oficial|corrigid[oa]|real final|v\d+)(?=$|[ _\-])', ''
    $t = $t -replace '(?i)[ _\-](v?final|ofc|oficial|corrigid[oa]|real)$', ''
    Limpar ($t -replace '_', ' ')
}
function Radical([string]$nome) {
    $t = ([IO.Path]::GetFileNameWithoutExtension($nome)).ToLower()
    $t = SemAcento $t
    $t = $t -replace '\(\d+\)', ''
    $t = $t -replace '(v?final|finais|ofc|oficial|corrigid[oa]|real|alterado|editado|legendado|_leg\b|com musica|sem musica|comselo|v\d+)', ''
    do { $antes = $t; $t = $t -replace '[ _\-]+\d{1,2}$', '' -replace '[ _\-]+$', '' } while ($t -ne $antes)
    $t -replace '[^a-z0-9]', ''
}
function Sob([string]$p, [string]$b) { $p.StartsWith($b.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $p -ieq $b.TrimEnd('\') }
function SemDrive([string]$p) { $p.Substring(3) }

# ---------------------------------------------------------------- clientes
# prefixo|cliente|grupo(Clientes/Freelas)|HD destino (C/S)
$tabClientes = @'
{C}00. Marca Página|Marca Pagina|Clientes|S
{C}01. Separ.acoes|Vivi|Clientes|C
{C}Beatriz_Reels|Vivi|Clientes|C
{C}Nailde_reels|Vivi|Clientes|C
{C}03. Hypper|Hypper|Clientes|C
{C}Curso_Advocacia 6D|Ale Busato|Clientes|C
{C}05. Freelas\01. Desejo Insanidade|Desejo e Insanidade|Freelas|C
{C}05. Freelas\02. mocha|Mocha|Freelas|C
{C}05. Freelas\03. Gabriela|Gabriela|Freelas|C
{C}05. Freelas\Alessandro|Alessandro|Freelas|C
{C}05. Freelas\Bianca_15|Bianca|Freelas|C
{C}05. Freelas\Cauan|Cauan|Freelas|C
{C}05. Freelas\Nova pasta|Haru|Freelas|C
{C}05. Freelas\Video_spotify|Spotify|Freelas|C
{C}05. Freelas|_Sem freela|Freelas|C
{S}Desktop\00_Projetos Ativos\Marca Página|Marca Pagina|Clientes|S
{S}Desktop\00_Projetos Ativos\00. Hypper|Hypper|Clientes|C
{S}Desktop\00_Projetos Ativos\Historia de divorcio|Vivi|Clientes|C
{S}Desktop\Ale Busato|Ale Busato|Clientes|C
{S}Desktop\Yana|Yana|Clientes|C
{S}Desktop\Luiz|Luiz|Clientes|C
{S}Desktop\Cortes_Luiz|Luiz|Clientes|C
{S}Desktop\Jovem Aventura|Jovem Aventura|Clientes|C
{S}Desktop\Lenise|Lenise|Freelas|C
{S}Desktop\universe|Universe|Freelas|C
{S}Desktop\Freelas diversos|Clube R1|Freelas|C
'@
$Clientes = foreach ($l in ($tabClientes -split "`r?`n" | Where-Object { $_ })) {
    $cc = $l.Split('|'); [pscustomobject]@{ Prefixo = ($cc[0] -replace '\{C\}', $C -replace '\{S\}', $S); Cliente = $cc[1]; Grupo = $cc[2]; HD = $(if ($cc[3] -eq 'C') { $C } else { $S }) }
}
$Clientes = $Clientes | Sort-Object { $_.Prefixo.Length } -Descending

# ---------------------------------------------------------------- conteúdos
# prefixo|modo|titulo|flags      modos: avulso, lote, revisar, assets, projetos, arte, carrossel
$MP0 = '{S}Desktop\00_Projetos Ativos\Marca Página\00. Marca Página'
$MPS = '{S}Desktop\00_Projetos Ativos\Marca Página'
$R = "$MP0\02. Reels"
$tabConteudos = @"
{C}00. Marca Página|avulso||
{C}00. Marca Página\00. Solo Levelling - EPS|revisar||
{C}00. Marca Página\00. Vídeos\01. CCXP|lote|CCXP Gincana|
{C}00. Marca Página\00. Vídeos\01. Novembro_semana1|lote|Reels Novembro Semana 1|
{C}00. Marca Página\01. Thumbs|assets|Thumbs|
{C}00. Marca Página\01. Youtube|avulso||
{C}00. Marca Página\01. Youtube\Berserk|revisar||
{C}00. Marca Página\01. Youtube\cacadores mais temidos|lote|Cacadores Mais Temidos|
{C}00. Marca Página\01. Youtube\Ep01|revisar||
{C}00. Marca Página\01. Youtube\EP05|lote|Solo Leveling EP05|
{C}00. Marca Página\01. Youtube\EP06|lote|Solo Leveling EP06|
{C}00. Marca Página\01. Youtube\ep09|lote|Solo Leveling EP09|
{C}00. Marca Página\01. Youtube\Ep3|lote|Solo Leveling EP03|
{C}00. Marca Página\01. Youtube\Export|avulso||
{C}00. Marca Página\01. Youtube\Jeju|lote|Ilha de Jeju|
{C}00. Marca Página\01. Youtube\jinwoox3monarcas|lote|Jinwoo x 3 Monarcas|
{C}00. Marca Página\01. Youtube\LUTA X ARQUITETO|lote|Luta Arquiteto|
{C}00. Marca Página\01. Youtube\monarcas explicados|lote|Monarcas Explicados|
{C}00. Marca Página\01. Youtube\Monstros_yt|lote|Monstros Mais Temidos|
{C}00. Marca Página\01. Youtube\origem do poder do jinwoo|lote|Origem do Poder do Jinwoo|
{C}00. Marca Página\01. Youtube\portal rank s do japao|lote|Portal Rank S Japao|
{C}00. Marca Página\01. Youtube\ranking jinwoo|lote|Ranking Habilidades Jinwoo|
{C}00. Marca Página\01. Youtube\season finale|lote|Solo Leveling Season Finale|
{C}00. Marca Página\01. Youtube\solo leveling_pre final|lote|Solo Leveling EP24|
{C}00. Marca Página\01. Youtube\THUMBS|assets|Thumbs|
{C}00. Marca Página\01. Youtube\Todas as sombras|lote|Todas as Sombras|
{C}00. Marca Página\02. Projetos|projetos||
{C}00. Marca Página\03. ID|assets|ID|
{C}00. Marca Página\04. News|revisar||
{C}00. Marca Página\05. Frame|avulso||
{C}00. Marca Página\CCXP25|lote|CCXP25|
{C}00. Marca Página\Video casamento|lote|Video Casamento|
{C}01. Separ.acoes|avulso||
{C}01. Separ.acoes\00. Vídeos\Tatiane|arte|Tatiane YouTube|
{C}01. Separ.acoes\00. Vídeos\01. Mayara|revisar||
{C}01. Separ.acoes\00. Vídeos\02. Beatriz|revisar||
{C}01. Separ.acoes\03. Frame_Vivi|lote|Montagem Feed|
{C}01. Separ.acoes\Beatryz Maynart|arte|Beatriz YouTube|
{C}01. Separ.acoes\Estelamar|arte|Estelamar YouTube|
{C}01. Separ.acoes\Maria Cleidilene|arte|Maria Cleidilene YouTube|
{C}01. Separ.acoes\Reels_Estelamar|lote|Estelamar Reels|
{C}01. Separ.acoes\Reels_mayara|lote|Mayara Reels|
{C}01. Separ.acoes\Tatiane_reels|lote|Tatiane Reels|
{C}Beatriz_Reels|lote|Beatriz Reels|
{C}Nailde_reels|lote|Nailde Reels|
{C}03. Hypper|avulso||
{C}03. Hypper\00. Tdonuts|lote|Tdonuts Recheios Microondas|
{C}03. Hypper\01. Frutassa|lote|Frutassa|
{C}03. Hypper\02. Origens|lote|Origens|
{C}03. Hypper\02. Origens\Origens|lote|Origens Cafes|
{C}03. Hypper\eXPORT|lote|Tdonuts Treinamento|REVISAR TITULO
{C}Curso_Advocacia 6D|lote|Curso Advocacia 6D|
{C}05. Freelas|revisar||
{C}05. Freelas\01. Desejo Insanidade|lote|Video Promo Desejo e Insanidade|
{C}05. Freelas\01. Desejo Insanidade\Cassandra|revisar||
{C}05. Freelas\01. Desejo Insanidade\DESEJO E INSANIDADE_VIDEO FSA|revisar||
{C}05. Freelas\01. Desejo Insanidade\LOGO BARROCO|assets|Logo|
{C}05. Freelas\02. mocha|assets|Identidade|
{C}05. Freelas\03. Gabriela|avulso||
{C}05. Freelas\03. Gabriela\01. Teste|lote|Comece Agora|
{C}05. Freelas\03. Gabriela\2 videos_26.02|lote|Videos 26-02|
{C}05. Freelas\03. Gabriela\99. Projetos|avulso||
{C}05. Freelas\Alessandro|avulso||
{C}05. Freelas\Alessandro\Sabbia Sports|lote|Sabbia Sports|
{C}05. Freelas\Alessandro\Sabbia Sports\MARCA_SABBIA|assets|Marca Sabbia|
{C}05. Freelas\Bianca_15|lote|Bianca 15 Anos|REVISAR TITULO
{C}05. Freelas\Cauan|avulso||
{C}05. Freelas\Cauan\Quanto de dinheiro você precisa para morar fora|revisar||
{C}05. Freelas\Cauan\vid_denuncia|revisar||
{C}05. Freelas\Cauan\vid1|revisar||
{C}05. Freelas\Cauan\vid2|revisar||
{C}05. Freelas\Nova pasta|lote|Haru Despedida|REVISAR TITULO
{C}05. Freelas\Teste|revisar||
{C}05. Freelas\Video_spotify|lote|Video Spotify|REVISAR TITULO
{C}05. Freelas\Video_spotify\videos nina|revisar||
{S}Desktop\00_Projetos Ativos\00. Hypper|avulso||
{S}Desktop\00_Projetos Ativos\00. Hypper\03. Oh creamy|lote|Oh Creamy|
{S}Desktop\00_Projetos Ativos\00. Hypper\03. Oh creamy\logo|assets|Oh Creamy Logo|
{S}Desktop\00_Projetos Ativos\00. Hypper\1x|revisar||
{S}Desktop\00_Projetos Ativos\00. Hypper\99. NFs|assets|NFs|
{S}Desktop\00_Projetos Ativos\00. Hypper\goodcop.aep_AME|revisar||
{S}Desktop\00_Projetos Ativos\00. Hypper\Mr. Cheney|lote|Mr Cheney Vinheta|SEMLOGO
{S}Desktop\00_Projetos Ativos\Historia de divorcio\01. Vídeo patrocinio|lote|Video Patrocinio|
{S}Desktop\00_Projetos Ativos\Historia de divorcio\04. 4 nov|lote|Karine Moraes|
{S}Desktop\00_Projetos Ativos\Historia de divorcio\04. 4 nov\Arte|arte|Karine Moraes|
{S}Desktop\Ale Busato|avulso||
{S}Desktop\Ale Busato\Melhorias site|assets|Melhorias Site|
{S}Desktop\Yana|avulso||
{S}Desktop\Yana\Ads|lote|Ads|
{S}Desktop\Yana\Anúncios|lote|Anuncios|
{S}Desktop\Yana\Trilhas|lote|Curso Trilhas|
{S}Desktop\Yana\Trilhas\editados\Biblioteca de movimentos - Editados|lote|Biblioteca de Movimentos|
{S}Desktop\Yana\images|revisar||
{S}Desktop\Yana\Material respiracao|revisar||
{S}Desktop\Yana\mEDITATICVO|revisar||
{S}Desktop\Luiz|avulso||
{S}Desktop\Luiz\Ricardo Nunes|lote|Ricardo Nunes Teaser|REVISAR TITULO
{S}Desktop\Cortes_Luiz|lote|Cortes|
{S}Desktop\Jovem Aventura|assets|Identidade|
{S}Desktop\Lenise|assets||
{S}Desktop\universe|assets||
{S}Desktop\Freelas diversos|lote|Retrospectiva Clube R1|
$MPS|avulso||
$MPS\Arquivo|avulso||
$MPS\Bruno - Abrilmaio|avulso||
$MPS\Frieren|lote|Frieren|
$MPS\Koe no Katachi|lote|Koe no Katachi|
$MPS\Marca Pag|avulso||
$MPS\Marca Pag\02. Pre CCXP + longos|lote|Pre CCXP|
$MPS\Marca Pag\04. Pre ccxp - leva 2|lote|Pre CCXP Leva 2|
$MPS\Marca Pag\CCXP|revisar||
$MPS\Marca Pag\Export|avulso||
$MPS\Marca Pag\Leva_dez_23|lote|Leva Dezembro|
$MPS\Marca Pag\OLHAR OQ É|revisar||
$MPS\Marca Pag\Supercombo|lote|Supercombo|
$MPS\Marca Pag\Valley|revisar||
$MPS\Marca Pagina|avulso||
$MPS\Marca Pagina\CCXP|revisar||
$MPS\Marca Pagina\Lives|lote|Lives|
$MPS\Reels|avulso||
$MPS\Reels\11-04|lote|Reels 11-04|
$MPS\Reels\reels novos|revisar||
$MPS\spider blue|revisar||
$MPS\teasers|lote|Teasers|
$MPS\Youtube|avulso||
$MPS\Youtube\Proj|projetos||
$MPS\Youtube\Videos|revisar||
$MP0|avulso||
$MP0\_Assets|assets|Audio|
$MP0\01. Projetos|projetos||
$MP0\03. Carrossel|revisar||
$MP0\03. Carrossel\drive-download-20260106T190359Z-3-001|carrossel|Carrossel Janeiro|REVISAR TITULO
$MP0\03. Carrossel\Melhores coadjuvantes-20260109T194939Z-3-001|carrossel|Carrossel Melhores Coadjuvantes|
$MP0\Ads e reels Janeiro|lote|Ads e Reels Janeiro|
$MP0\Ads e reels Janeiro\Ad|revisar||
$MP0\Arquivo|avulso||
$MP0\CopyPasta|revisar||
$MP0\ID_Visual|assets|ID Visual|
$MP0\Leva_03.20 Masks|projetos||
$R|avulso||
$R\00. CCXP25|projetos||
$R\00. Leva nova|lote|Reels Leva Nova|
$R\04_06|lote|Reels 04-06|
$R\10. Outurbo|lote|Reels Outubro|
$R\10-07|lote|Reels 10-07|
$R\11. novembro|lote|Reels Novembro|
$R\12. Dezembro|lote|Reels Dezembro|
$R\24.05|lote|Reels 24-05|
$R\26.02|lote|Reels 26-02|
$R\30.05|lote|Reels 30-05|
$R\af adesivos|revisar||
$R\AF_EVENTO|lote|Anime Friends Panini|
$R\Animes\Sora_akudama_durarara|lote|Reels Sora Akudama Durarara|
$R\BLOCO 22.09.25|lote|Reels Bloco 22-09|
$R\clube e ghibli|lote|Clube e Ghibli|
$R\como treinar seu dragao|lote|Como Treinar Seu Dragao|
$R\cortes clube|lote|Cortes Clube|
$R\Credenciais ccxp|lote|Credenciais CCXP|
$R\demon slayer|lote|Demon Slayer|
$R\demoreel_af|revisar||
$R\entrevista cosplay|lote|Entrevista Cosplay|
$R\Entrevistas|lote|Entrevistas|
$R\evangelion|lote|Evangelion|
$R\Export|avulso||
$R\gamescom latam|lote|Gamescom Latam|
$R\gibli e mine|lote|Ghibli e Minecraft|
$R\giglio|lote|Giglio|
$R\jogo do diabo|lote|Jogo do Diabo|
$R\Julho|lote|Reels Julho|
$R\Kishotenketsu|lote|Kishotenketsu|
$R\ler manga|lote|Ler Manga|
$R\mercado livre|lote|Mercado Livre|
$R\Nova pasta|revisar||
$R\Proxies|revisar||
$R\reels dezembro 25|lote|Reels Dezembro 25|
$R\Reels_14.03|lote|Reels 14-03|
$R\reels_abril_01|lote|Reels Abril 01|
$R\Reels_abril_2 e 3|lote|Reels Abril 02 e 03|
$R\starwars|lote|Star Wars|
$R\superman|lote|Superman|
$R\superman review|lote|Superman Review|
$R\thunderbolts|lote|Thunderbolts|
$R\TIM|lote|TIM|
"@
$Conteudos = foreach ($l in ($tabConteudos -split "`r?`n" | Where-Object { $_ })) {
    $cc = $l.Split('|'); [pscustomobject]@{ Prefixo = ($cc[0] -replace '\{C\}', $C -replace '\{S\}', $S); Modo = $cc[1]; Titulo = $cc[2]; Flags = $cc[3] }
}
$Conteudos = $Conteudos | Sort-Object { $_.Prefixo.Length } -Descending

# ---------------------------------------------------------------- exceções por arquivo
# caminho relativo ao HD|cliente|titulo do conteudo|acao (EXPORT/REVISAR/ASSETS:<sub>)|nota
$tabArq = @'
{C}01. Separ.acoes\tatiane_YT_final.mp4|Vivi|Tatiane YouTube|EXPORT|
{C}01. Separ.acoes\tatiane_yt.mp4|Vivi|Tatiane YouTube|REVISAR|versao anterior do tatiane_YT_final
{C}01. Separ.acoes\tatiane_yt_1.mp4|Vivi|Tatiane YouTube|REVISAR|versao anterior do tatiane_YT_final
{C}01. Separ.acoes\Tatiane Nascimento.mp4|Vivi|Tatiane YouTube|REVISAR|versao antiga do YouTube da Tatiane (mesma duracao, 1 Mbps)
{C}01. Separ.acoes\Beatriz_YT.mp4|Vivi|Beatriz YouTube|EXPORT|
{C}01. Separ.acoes\estelamar_yt.mp4|Vivi|Estelamar YouTube|EXPORT|REVISAR VERSAO: existe tambem Estelamar\Estelamar.mp4 (51 min, 1 Mbps)
{C}01. Separ.acoes\Estelamar\Estelamar.mp4|Vivi|Estelamar YouTube|EXPORT|REVISAR VERSAO: 51 min x 42 min do estelamar_yt
{C}01. Separ.acoes\final_maria.mov|Vivi|Maria Cleidilene YouTube|EXPORT|REVISAR VERSAO: 38 s, pode ser teaser
{C}01. Separ.acoes\Maria Cleidilene\MARIA CLEIDILEINE.mp4|Vivi|Maria Cleidilene YouTube|EXPORT|REVISAR VERSAO: 51 min 1 Mbps x 47 min do _YT (Frame)
{C}00. Marca Página\05. Frame\maria cleidilene_YT.mp4|Vivi|Maria Cleidilene YouTube|EXPORT|REVISAR VERSAO: 47 min x 51 min do MARIA CLEIDILEINE
{C}00. Marca Página\05. Frame\Cassia_YT.mp4|Vivi|Cassia YouTube|EXPORT|
{C}00. Marca Página\05. Frame\Cris_yt.mp4|Vivi|Cris YouTube|EXPORT|
{C}00. Marca Página\05. Frame\Nailde.mp4|Vivi|Nailde YouTube|EXPORT|REVISAR VERSAO: 47 min x 48 min do Nailde_yt
{C}Nailde_reels\Nailde_yt.mp4|Vivi|Nailde YouTube|EXPORT|REVISAR VERSAO: 48 min x 47 min do Nailde (Frame)
{C}01. Separ.acoes\Cópia de Thumb - Vivi.jpg|Vivi||ASSETS:Thumbs|
{C}01. Separ.acoes\Cópia de Thumb - Vivi (1).jpg|Vivi||ASSETS:Thumbs|
{C}00. Marca Página\05. Frame\Cacadores.mp4|Marca Pagina|Cacadores Mais Temidos|EXPORT|REVISAR VERSAO: tem outro Cacadores.mp4 na raiz (tamanho diferente)
{C}00. Marca Página\Cacadores.mp4|Marca Pagina|Cacadores Mais Temidos|EXPORT|REVISAR VERSAO: tem outro Cacadores.mp4 no 05. Frame
{C}00. Marca Página\01. Youtube\ep06.mp4|Marca Pagina|Solo Leveling EP06|EXPORT|
{C}00. Marca Página\01. Youtube\ep06_1.mp4|Marca Pagina|Solo Leveling EP06|EXPORT|
{C}00. Marca Página\01. Youtube\ep10_yt.mp4|Marca Pagina|Solo Leveling EP10|EXPORT|
{C}00. Marca Página\01. Youtube\ep_10_yt_final.mp4|Marca Pagina|Solo Leveling EP10|EXPORT|
{C}00. Marca Página\01. Youtube\EP24_yt_final.mp4|Marca Pagina|Solo Leveling EP24|EXPORT|
{C}00. Marca Página\01. Youtube\monarcas explicados.mp4|Marca Pagina|Monarcas Explicados|EXPORT|
{C}00. Marca Página\01. Youtube\monstros mais temidos.mp4|Marca Pagina|Monstros Mais Temidos|EXPORT|
{C}00. Marca Página\01. Youtube\portal rank s japao.mp4|Marca Pagina|Portal Rank S Japao|EXPORT|
{C}00. Marca Página\01. Youtube\RANKING habilidade JINWOO.mp4|Marca Pagina|Ranking Habilidades Jinwoo|EXPORT|
{C}00. Marca Página\01. Youtube\ilha de jeju_combate completo.mp4|Marca Pagina|Ilha de Jeju|EXPORT|
{C}00. Marca Página\01. Youtube\Export\Luta arquiteto.mp4|Marca Pagina|Luta Arquiteto|EXPORT|
{C}00. Marca Página\01. Youtube\video final_xdongsoo.mp4|Marca Pagina|Xdongsoo|EXPORT|
{C}00. Marca Página\01. Youtube\fundo.mp4|Marca Pagina||REVISAR|fundo (6 Mbps), provavelmente material de edicao
{C}03. Hypper\Vinheta - Tdonuts.MOV|Hypper||ASSETS:Vinhetas|
{C}03. Hypper\02. Origens\logo_animado.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\00_Projetos Ativos\00. Hypper\cremoso.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\00_Projetos Ativos\00. Hypper\Intro crepefy.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\00_Projetos Ativos\00. Hypper\origens_intro.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\00_Projetos Ativos\00. Hypper\origens_saida.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\00_Projetos Ativos\00. Hypper\Logo Mr Cheney.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\00_Projetos Ativos\00. Hypper\logo_animado_v1.mp4|Hypper||ASSETS:Vinhetas|
{S}Desktop\Ale Busato\Módulo I - Advocacia 6D.mp4|Ale Busato|Curso Advocacia 6D|EXPORT|REVISAR VERSAO: mesma duracao do mod1.mp4 (Cinza), qualidade maior
{S}Desktop\Ale Busato\sala secreta 1.mp4|Ale Busato|Curso Advocacia 6D|EXPORT|REVISAR VERSAO: mesma duracao do diversificacao de renda.mp4 (Cinza), qualidade maior
{S}Desktop\Ale Busato\mod3.mp4|Ale Busato||REVISAR|copia da gravacao de Zoom de 06/03/2024
{S}Desktop\Ale Busato\video1181860626.mp4|Ale Busato||REVISAR|copia da gravacao de Zoom Mod. III
{S}Desktop\Ale Busato\corte1.mp4|Ale Busato|Corte 1|EXPORT|REVISAR TITULO
{C}05. Freelas\01. Desejo Insanidade\vfinal.mp4|Desejo e Insanidade|Video Promo Desejo e Insanidade|EXPORT|REVISAR VERSAO: as outras versoes de 3 min foram para 90. A revisar
{C}05. Freelas\03. Gabriela\nao basta ser visto.mp4|Gabriela|Nao Basta Ser Visto|EXPORT|
{C}05. Freelas\03. Gabriela\99. Projetos\oq postar nos stories.mp4|Gabriela|O Que Postar nos Stories|EXPORT|
{C}05. Freelas\plano_rd.mp4|_Sem freela||REVISAR|1h49, 3 Mbps, sem freela identificado
'@
$Arq = @{}
foreach ($l in ($tabArq -split "`r?`n" | Where-Object { $_ })) {
    $cc = $l.Split('|'); $k = ($cc[0] -replace '\{C\}', $C -replace '\{S\}', $S)
    $Arq[$k] = [pscustomobject]@{ Cliente = $cc[1]; Titulo = $cc[2]; Acao = $cc[3]; Nota = $cc[4] }
}
# Na Desejo e Insanidade, só o vfinal fica; os outros vídeos soltos da raiz vão para revisar.
$reDesejoRaiz = [regex]::Escape("$($C)05. Freelas\01. Desejo Insanidade\") + '[^\\]+\.(mp4|mov)$'

# títulos por regex em pastas "avulso": prefixo da pasta|regex do nome|titulo
$tabTitRe = @'
{S}Desktop\Luiz|(?i)^LUIZ_Ghost|Ghost
{S}Desktop\Luiz|(?i)^luiz_CTA|Ghost
{S}Desktop\Luiz|(?i)^reels_luiz|Reels
{C}05. Freelas\Cauan|(?i)^Denuncia|Denuncia
{C}05. Freelas\Cauan|(?i)^Rugby|Rugby
{C}05. Freelas\Cauan|(?i)^MORAR FORA|Morar Fora
{C}05. Freelas\Alessandro|(?i)^Sabbia|Sabbia Sports
'@
$TitRe = foreach ($l in ($tabTitRe -split "`r?`n" | Where-Object { $_ })) { $cc = $l.Split('|'); [pscustomobject]@{ Pasta = ($cc[0] -replace '\{C\}', $C -replace '\{S\}', $S); Re = $cc[1]; Titulo = $cc[2] } }

# ---------------------------------------------------------------- pastas inteiras (sem classificar)
$Pastas = @(
    @("$($S)Desktop\Edição\Brocolis Fízika.ai", "$($S)04. Pessoal\Backup 2022\Brocolis Fizika.ai", 'MOVER', 'pessoal', ''),
    @("$($S)Desktop\Tic Pic", "$($S)04. Pessoal\Tic Pic", 'MOVER_PASTA', 'pessoal', ''),
    @("$($S)Desktop\Canal Ia", "$($S)04. Pessoal\Canal IA", 'MOVER_PASTA', 'pessoal', ''),
    @("$($S)Desktop\Pessoal", "$($S)04. Pessoal\Pessoal", 'MOVER_PASTA', 'pessoal', ''),
    @("$($S)Desktop\Backup", "$($S)04. Pessoal\Backup 2022", 'MOVER_PASTA', 'pessoal', ''),
    @("$($S)Desktop\Edição", "$($S)_Para apagar\Seagate\Desktop\Edição", 'MOVER_PASTA', 'lixo', 'ja copiada pro Mac e conferida em 24/10'),
    @("$($S)Desktop\OL_Transition_11[1]", "$($S)03. Recursos de Edicao\OL_Transition_11", 'MOVER_PASTA', 'recurso', ''),
    @("$($S)Backup_Helen", "$($S)90. A revisar\Backup_Helen", 'MOVER_PASTA', 'revisar', 'backup do computador da Helen, sem classificar'),
    @("$($S)found.000", "$($S)99. Recuperados\found.000", 'MOVER_PASTA', 'recuperado', ''),
    @("$($S)found.001", "$($S)99. Recuperados\found.001", 'MOVER_PASTA', 'recuperado', ''),
    @("$($S)Desktop\desktop.ini", "$($S)_Para apagar\Seagate\Desktop\desktop.ini", 'MOVER', 'lixo', ''),
    @("$($S)Desktop\~`$ do list.docx", "$($S)_Para apagar\Seagate\Desktop\~`$ do list.docx", 'MOVER', 'lixo', ''),
    @("$($S)Desktop\~`$mposition Juliano.docx", "$($S)_Para apagar\Seagate\Desktop\~`$mposition Juliano.docx", 'MOVER', 'lixo', '')
)
$PrefixosPastas = $Pastas | ForEach-Object { $_[0] }

# ---------------------------------------------------------------- regras de tipo
$extVideo = '.mp4', '.mov', '.m4v', '.mxf', '.avi', '.mkv', '.mts', '.wmv', '.mpeg', '.mpg', '.webm'
$extProjeto = '.prproj', '.aep', '.drp', '.psd', '.ai', '.aup3', '.sesx', '.prmf', '.aegraphic', '.mogrt', '.svg', '.indd'
$extImagem = '.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif', '.heic', '.tif', '.tiff', '.bmp'
$extFonte = '.ttf', '.otf', '.woff', '.woff2'
$reCache = '(?i)\\(Adobe Premiere Pro (\(Beta\) )?(Audio Previews|Video Previews|Auto-Save)|Adobe After Effects Auto-Save|Media Cache( Files)?|__MACOSX)\\|\\(desktop\.ini|Thumbs\.db|\.DS_Store|~\$[^\\]*)$|\.(cfa|pek|tmp)$|\.\d+\.\d+\.m4v$|\.aup3-(shm|wal)$'
$reBaixado = '(?i)\((\d{3,4}p|4K)[^)]*youtube\)|videoplayback|\[(Erai-raws|Judas|AnimeRG)\]|x265|WEBRip|S\d{1,2}E\d{1,3}\b|Episódio|WhatsApp Video|Vídeo do WhatsApp|#\w|green screen|Top 30|ezmp3|\s\(\d+\)\.(mp4|mkv)$|Movie CLIP|Official|-esv2-|｜|Prime Video'
$reBaixadoCase = 'Trailer|TRAILER|Opening|Scene'
$reCamera = '(?i)bruto|[ _]raw\b|^(C\d{4}|DSC|_?MG_|MVI_|GX\d|GH\d|GOPR|IMG_|A\d{3}_|DJI_|PXL_|VID_|\d{8}_\d{6}|MAH\d|P\d{7}|clip-|M\d{4}|Img \d+)|\((Audio|Video|B-Roll)\)|^Teleprompter-|^\d{4}-\d\d-\d\d[ _-]\d\d[-.]\d\d[-.]\d\d|^video\d{9,10}\.|ScreenRecording|^copy_[0-9A-F-]{20,}|^[0-9a-f]{32}\.'
$rePastaBruto = '(?i)\\(brutos?|raw|footage|grava\w*|proxies|brolls?|brools|aguardando edi\w*|MP4_\d|DCIM|PRIVATE|fotos( PB| Crunchyroll)?|Cart[aã]o \d+|Adobe Audition Interchange|Adobe Premiere Pro Captured and Generated|CopyPasta|Premiere Composer Files|Motion Graphics Template Media)\\'
$reGenerico = '(?i)^(Nested )?Sequence \d+|^Comp \d|teste|^sajhg|^dasd|^dsds|^v\d+\.mp4$|^untitled'
$reLogo = '(?i)\b(logo|vinheta|vinhe?ta|intro)\b'
$reCapa = '(?i)thumb|capa'
$reExportPasta = '(?i)\\(export|exports|editados|final|finais|renders?)\\'

function Dur($r) { if ($r.duracao_s) { [double]::Parse($r.duracao_s.Replace(',', '.'), $inv) } else { 0 } }

function TipoVideo($r) {
    $leaf = Split-Path $r.caminho -Leaf
    $ext = [IO.Path]::GetExtension($leaf)
    $d = Dur $r; $b = [int64]$r.tamanho
    $mbps = if ($d -gt 0) { $b * 8 / 1e6 / $d } else { -1 }
    if ($leaf -match $reBaixado -or $leaf -cmatch $reBaixadoCase -or $ext -ieq '.mkv') { return 'baixado' }
    if ($leaf -match $reCamera) { return 'bruto' }
    if ($r.caminho -match $rePastaBruto) { return 'bruto' }
    $emExport = $r.caminho -match $reExportPasta
    if ($ext -ieq '.mov' -and -not $emExport -and $leaf -notmatch $reMarcaFinal) { return 'bruto' }
    if ($ext -ceq '.MP4' -and $mbps -ge 25) { return 'bruto' }
    if ($ext -in '.mxf', '.mts', '.avi', '.mpeg', '.mpg', '.webm') { return 'bruto' }
    if ($leaf -match $reGenerico) { return 'generico' }
    if ($b -lt 1MB -or ($d -gt 0 -and $d -lt 3)) { return 'generico' }
    return 'export'
}

# ---------------------------------------------------------------- leitura
$linhas = New-Object System.Collections.Generic.List[object]
foreach ($n in 'Cinza', 'Seagate') { foreach ($r in (Import-Csv (Join-Path $base "inventario_$n.csv") -Delimiter ';')) { $linhas.Add($r) } }

$plano = New-Object System.Collections.Generic.List[object]
function Add($origem, $destino, $acao, $tipo, $obs, $cliente, $conteudo, $tam) {
    $plano.Add([pscustomobject]@{ origem = $origem; destino = $destino; acao = $acao; tipo = $tipo; observacao = $obs; cliente = $cliente; conteudo = $conteudo; tamanho = $tam })
}
function Acao($origem, $destino) { if ($origem.Substring(0, 3) -ieq $destino.Substring(0, 3)) { 'MOVER' } else { 'COPIAR' } }
function DestRevisar($hdCli, $p) { Join-Path $hdCli ("90. A revisar\" + $NomeHD[$p.Substring(0, 3)] + '\' + (SemDrive $p)) }
function DestApagar($hdCli, $p) { Join-Path $hdCli ("_Para apagar\" + $NomeHD[$p.Substring(0, 3)] + '\' + (SemDrive $p)) }

foreach ($p in $Pastas) {
    $tam = 0; foreach ($r in $linhas) { if (Sob $r.caminho $p[0]) { $tam += [int64]$r.tamanho } }
    Add $p[0] $p[1] $p[2] $p[3] $p[4] '' '' $tam
}

# Itens finais de cada conteúdo, pra decidir nomes depois.
$finais = New-Object System.Collections.Generic.List[object]
$pendentes = New-Object System.Collections.Generic.List[object]   # projetos/arte/capas que dependem do conteúdo
$naoMapeados = New-Object System.Collections.Generic.List[string]

foreach ($r in $linhas) {
    $p = $r.caminho
    $coberto = $false; foreach ($pp in $PrefixosPastas) { if (Sob $p $pp) { $coberto = $true; break } }
    if ($coberto) { continue }
    $cli = $Clientes | Where-Object { Sob $p $_.Prefixo } | Select-Object -First 1
    if (-not $cli) { $naoMapeados.Add($p); continue }
    $leaf = Split-Path $p -Leaf
    $ext = [IO.Path]::GetExtension($leaf).ToLower()
    $tam = [int64]$r.tamanho
    $hd = $cli.HD
    $raizCli = Join-Path $hd ("01. Clientes\" + $cli.Cliente); if ($cli.Grupo -eq 'Freelas') { $raizCli = Join-Path $hd ("02. Freelas\" + $cli.Cliente) }

    # exceção por arquivo
    if ($Arq.ContainsKey($p)) {
        $x = $Arq[$p]
        $cliX = $Clientes | Where-Object { $_.Cliente -eq $x.Cliente } | Select-Object -First 1
        $hdX = $cliX.HD; $raizX = Join-Path $hdX ("01. Clientes\" + $x.Cliente); if ($cliX.Grupo -eq 'Freelas') { $raizX = Join-Path $hdX ("02. Freelas\" + $x.Cliente) }
        if ($x.Acao -eq 'EXPORT') { $finais.Add([pscustomobject]@{ r = $r; Cliente = $x.Cliente; Raiz = $raizX; HD = $hdX; Titulo = $x.Titulo; Pasta = 'excecao:' + $x.Titulo; Modo = 'avulso'; Nota = $x.Nota; Flags = '' }); continue }
        if ($x.Acao -eq 'REVISAR') { $d = DestRevisar $hdX $p; Add $p $d (Acao $p $d) 'revisar' $x.Nota $x.Cliente $x.Titulo $tam; continue }
        if ($x.Acao -like 'ASSETS:*') { $d = Join-Path $raizX ("Assets\" + $x.Acao.Substring(7) + '\' + (Limpar ([IO.Path]::GetFileNameWithoutExtension($leaf))) + $ext); Add $p $d (Acao $p $d) 'asset' $x.Nota $x.Cliente '' $tam; continue }
    }
    if ($p -match $reDesejoRaiz) { $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) 'versao' 'versao/teste do video promo (a final e o vfinal.mp4)' $cli.Cliente '' $tam; continue }

    # cache e lixo
    if (($p -match $reCache) -or ($tam -eq 0 -and $ext -eq '.m4v')) { $d = DestApagar $hd $p; Add $p $d (Acao $p $d) 'cache' '' $cli.Cliente '' $tam; continue }

    $cont = $Conteudos | Where-Object { Sob $p $_.Prefixo } | Select-Object -First 1
    if (-not $cont) { $naoMapeados.Add($p); $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) 'revisar' 'NAO MAPEADO' $cli.Cliente '' $tam; continue }
    $rel = $p.Substring($cont.Prefixo.TrimEnd('\').Length + 1)

    if ($cont.Modo -eq 'revisar') { $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) 'revisar' '' $cli.Cliente '' $tam; continue }
    if ($cont.Modo -eq 'assets') {
        $sub = if ($cont.Titulo) { $cont.Titulo + '\' } else { '' }
        $d = Join-Path $raizCli ("Assets\" + $sub + $rel); Add $p $d (Acao $p $d) 'asset' '' $cli.Cliente '' $tam; continue
    }
    if ($cont.Modo -eq 'projetos') {
        if ($extProjeto -contains $ext) { $d = Join-Path $raizCli ("Projetos sem conteudo\" + $p.Substring($cli.Prefixo.TrimEnd('\').Length + 1)); Add $p $d (Acao $p $d) 'projeto' 'projeto sem conteudo identificado' $cli.Cliente '' $tam }
        else { $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) 'revisar' '' $cli.Cliente '' $tam }
        continue
    }
    if ($cont.Modo -eq 'arte') { $pendentes.Add([pscustomobject]@{ r = $r; Cliente = $cli.Cliente; Raiz = $raizCli; HD = $hd; Titulo = $cont.Titulo; Tipo = 'projeto'; Rel = $rel }); continue }
    if ($cont.Modo -eq 'carrossel') {
        if ($extImagem -contains $ext) { $finais.Add([pscustomobject]@{ r = $r; Cliente = $cli.Cliente; Raiz = $raizCli; HD = $hd; Titulo = $cont.Titulo; Pasta = $cont.Prefixo; Modo = 'lote'; Nota = ''; Flags = $cont.Flags }) }
        else { $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) 'revisar' '' $cli.Cliente '' $tam }
        continue
    }

    # lote / avulso
    $pasta = Split-Path $p -Parent
    if ($extProjeto -contains $ext) {
        if ($cont.Modo -eq 'lote') { $pendentes.Add([pscustomobject]@{ r = $r; Cliente = $cli.Cliente; Raiz = $raizCli; HD = $hd; Titulo = $cont.Titulo; Tipo = 'projeto'; Rel = $rel }) }
        else { $d = Join-Path $raizCli ("Projetos sem conteudo\" + $p.Substring($cli.Prefixo.TrimEnd('\').Length + 1)); Add $p $d (Acao $p $d) 'projeto' 'projeto sem conteudo identificado' $cli.Cliente '' $tam }
        continue
    }
    if ($extFonte -contains $ext) { $d = Join-Path $raizCli ("Assets\Fontes\" + $leaf); Add $p $d (Acao $p $d) 'asset' '' $cli.Cliente '' $tam; continue }
    if ($extVideo -contains $ext) {
        $tv = TipoVideo $r
        if ($tv -eq 'export' -and $leaf -match $reLogo -and $cont.Flags -notmatch 'SEMLOGO') {
            $d = Join-Path $raizCli ("Assets\Vinhetas\" + (Limpar ([IO.Path]::GetFileNameWithoutExtension($leaf))) + $ext); Add $p $d (Acao $p $d) 'asset' 'logo/vinheta animada' $cli.Cliente '' $tam; continue
        }
        if ($tv -eq 'export') {
            $tit = $cont.Titulo
            if ($cont.Modo -eq 'avulso') {
                $tit = $null
                foreach ($t in $TitRe) { if ((Sob $p $t.Pasta) -and $leaf -match $t.Re) { $tit = $t.Titulo; break } }
            }
            $finais.Add([pscustomobject]@{ r = $r; Cliente = $cli.Cliente; Raiz = $raizCli; HD = $hd; Titulo = $tit; Pasta = $(if ($cont.Modo -eq 'lote') { $cont.Prefixo } else { $pasta }); Modo = $cont.Modo; Nota = ''; Flags = $cont.Flags })
            continue
        }
        $obs = @{ bruto = 'bruto'; baixado = 'material baixado (b-roll/referencia)'; generico = 'nome generico/teste' }[$tv]
        $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) $tv $obs $cli.Cliente '' $tam; continue
    }
    if ($extImagem -contains $ext -and $leaf -match $reCapa -and $cont.Modo -eq 'lote') {
        $pendentes.Add([pscustomobject]@{ r = $r; Cliente = $cli.Cliente; Raiz = $raizCli; HD = $hd; Titulo = $cont.Titulo; Tipo = 'capa'; Rel = $rel }); continue
    }
    if ($extImagem -contains $ext -and $leaf -match $reLogo) { $d = Join-Path $raizCli ("Assets\Logos\" + $leaf); Add $p $d (Acao $p $d) 'asset' '' $cli.Cliente '' $tam; continue }
    $d = DestRevisar $hd $p; Add $p $d (Acao $p $d) 'revisar' $(if ($ext -in '.wav', '.mp3', '.m4a', '.aac') { 'audio' } else { '' }) $cli.Cliente '' $tam
}

# ---------------------------------------------------------------- versões, duplicatas e nomes
# 1) Agrupa por pasta de origem + radical + duração parecida.
$grupos = $finais | Group-Object { if ($extImagem -contains [IO.Path]::GetExtension($_.r.caminho).ToLower()) { $_.r.caminho } else { $_.Pasta + '|' + (Radical (Split-Path $_.r.caminho -Leaf)) } }
$mantidos = New-Object System.Collections.Generic.List[object]
foreach ($g in $grupos) {
    $itens = @($g.Group | Sort-Object { Dur $_.r })
    # quebra em clusters de duração (diferença <= 2 s)
    $clusters = New-Object System.Collections.Generic.List[object]; $atual = $null; $ult = -100
    foreach ($i in $itens) { $dd = Dur $i.r; if ($null -eq $atual -or [math]::Abs($dd - $ult) -gt 0.5) { $atual = New-Object System.Collections.Generic.List[object]; $clusters.Add($atual) }; $atual.Add($i); $ult = $dd }
    foreach ($cl in $clusters) {
        if ($cl.Count -eq 1) { $mantidos.Add($cl[0]); continue }
        $marc = @($cl | Where-Object { (Split-Path $_.r.caminho -Leaf) -match $reMarcaFinal })
        $nomes = ($cl | ForEach-Object { Split-Path $_.r.caminho -Leaf }) -join ', '
        if ($marc.Count -eq 1) {
            $mantidos.Add($marc[0])
            foreach ($o in $cl) { if ($o -ne $marc[0]) { $d = DestRevisar $o.HD $o.r.caminho; Add $o.r.caminho $d (Acao $o.r.caminho $d) 'versao' ("versao anterior de " + (Split-Path $marc[0].r.caminho -Leaf)) $o.Cliente '' ([int64]$o.r.tamanho) } }
        } elseif ($marc.Count -gt 1) {
            foreach ($o in $cl) {
                if ($marc -contains $o) { $o.Nota = (($o.Nota + ' REVISAR VERSAO: mais de uma marcada como final (' + $nomes + ')').Trim()); $mantidos.Add($o) }
                else { $d = DestRevisar $o.HD $o.r.caminho; Add $o.r.caminho $d (Acao $o.r.caminho $d) 'versao' 'versao anterior' $o.Cliente '' ([int64]$o.r.tamanho) }
            }
        } else {
            $titComum = TituloDeArquivo (($cl | ForEach-Object { Split-Path $_.r.caminho -Leaf } | Sort-Object Length | Select-Object -First 1)); foreach ($o in $cl) { if ($o.Modo -eq 'avulso' -and -not $o.Titulo) { $o.Titulo = $titComum }; $o.Nota = (($o.Nota + ' REVISAR VERSAO: mesma duracao, nao sei qual e a final (' + $nomes + ')').Trim()); $mantidos.Add($o) }
        }
    }
}
# 2) Duplicatas exatas (mesmo tamanho em bytes e mesma duração) dentro do cliente.
$finaisOk = New-Object System.Collections.Generic.List[object]
foreach ($g in ($mantidos | Group-Object { $_.Cliente + '|' + $_.r.tamanho + '|' + $_.r.duracao_s })) {
    $ord = @($g.Group | Sort-Object { if ($_.r.caminho -match '\\Arquivo\\') { 1 } else { 0 } }, { $_.r.caminho })
    $finaisOk.Add($ord[0])
    for ($i = 1; $i -lt $ord.Count; $i++) { $o = $ord[$i]; $d = DestRevisar $o.HD $o.r.caminho; Add $o.r.caminho $d (Acao $o.r.caminho $d) 'duplicata' ("copia identica de " + $ord[0].r.caminho) $o.Cliente '' ([int64]$o.r.tamanho) }
}
# 3) Título de cada final avulso.
foreach ($f in $finaisOk) { if (-not $f.Titulo) { $f.Titulo = TituloDeArquivo (Split-Path $f.r.caminho -Leaf); if ($f.Titulo -match '^\d*$' -or $f.Titulo.Length -lt 3) { $f.Nota = ($f.Nota + ' REVISAR TITULO').Trim() } } }
# 4) Conteúdo = cliente + título. Data da pasta = arquivo mais antigo.
$palavrasNeutras = 'yt', 'youtube', 'reels', 'reelss', 'reel', 'video', 'videos', 'export', 'final', 'mp', 'v', 'de', 'do', 'da', 'e'
function Tokens($s) { ((SemAcento $s).ToLower() -replace '[^a-z ]', ' ').Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $palavrasNeutras -notcontains $_ } }
$infoConteudo = @{}
foreach ($g in ($finaisOk | Group-Object { $_.Cliente + '|' + $_.Titulo })) {
    $itens = @($g.Group | Sort-Object { $_.r.modificado }, { $_.r.caminho })
    $f0 = $itens[0]; $data0 = [datetime]::ParseExact($f0.r.modificado, 'yyyy-MM-dd HH:mm:ss', $inv)
    $titLimpo = Limpar $f0.Titulo
    $pastaC = Join-Path $f0.Raiz ("Conteudos\" + $data0.ToString('yyyy') + '\' + $data0.ToString('yyyy-MM') + '_' + $titLimpo)
    $infoConteudo[$g.Name] = $pastaC
    # nomes: numerado (se o nome do arquivo não acrescenta nada) ou descritivo
    $tokTit = @(Tokens ($f0.Titulo + ' ' + (Split-Path $f0.Pasta -Leaf)))
    $usados = @{}; $num = 0
    $multi = $itens.Count -gt 1
    $ordenados = $itens | Sort-Object { [regex]::Replace((Split-Path $_.r.caminho -Leaf).ToLower(), '\d+', { param($m) $m.Value.PadLeft(6, '0') }) }
    foreach ($f in $ordenados) {
        $leaf = Split-Path $f.r.caminho -Leaf; $ext = [IO.Path]::GetExtension($leaf).ToLower()
        $dt = [datetime]::ParseExact($f.r.modificado, 'yyyy-MM-dd HH:mm:ss', $inv)
        $tokArq = @(Tokens (TituloDeArquivo $leaf))
        $soNumero = ($tokArq | Where-Object { $tokTit -notcontains $_ }).Count -eq 0
        if (-not $multi) { $tf = $titLimpo }
        elseif ($soNumero -or $f.Modo -eq 'avulso' -or $extImagem -contains $ext) { $num++; $tf = "$titLimpo {0:D2}" -f $num }
        else { $tf = TituloDeArquivo $leaf }
        $nome = $dt.ToString('yyyy-MM-dd') + '_' + $f.Cliente + '_' + $tf
        $k = $nome.ToLower(); $n2 = 2
        while ($usados.ContainsKey($k + $ext)) { $nome = $dt.ToString('yyyy-MM-dd') + '_' + $f.Cliente + '_' + $tf + " $n2"; $k = $nome.ToLower(); $n2++ }
        $usados[$k + $ext] = 1
        $d = Join-Path $pastaC ($nome + $ext)
        $tipo = if ($extImagem -contains $ext) { 'final-imagem' } else { 'export' }
        Add $f.r.caminho $d (Acao $f.r.caminho $d) $tipo (($f.Nota + ' ' + $f.Flags).Trim() -replace 'SEMLOGO', '' ) $f.Cliente $titLimpo ([int64]$f.r.tamanho)
    }
}
# 5) Projetos, arte e capas ligados a um conteúdo.
foreach ($x in $pendentes) {
    $k = $x.Cliente + '|' + $x.Titulo; $p = $x.r.caminho; $tam = [int64]$x.r.tamanho
    $pastaC = $infoConteudo[$k]
    if (-not $pastaC) {
        if ($x.Tipo -eq 'projeto' -and ($extProjeto -contains [IO.Path]::GetExtension($p).ToLower())) { $d = Join-Path $x.Raiz ("Projetos sem conteudo\" + (Limpar $x.Titulo) + '\' + $x.Rel); Add $p $d (Acao $p $d) 'projeto' 'conteudo sem export final' $x.Cliente '' $tam }
        else { $d = DestRevisar $x.HD $p; Add $p $d (Acao $p $d) 'revisar' 'arte/capa de conteudo sem export final' $x.Cliente '' $tam }
        continue
    }
    if ($x.Tipo -eq 'capa') {
        $dt = [datetime]::ParseExact($x.r.modificado, 'yyyy-MM-dd HH:mm:ss', $inv); $ext = [IO.Path]::GetExtension($p).ToLower()
        $d = Join-Path $pastaC ($dt.ToString('yyyy-MM-dd') + '_' + $x.Cliente + '_' + (Split-Path $pastaC -Leaf).Substring(8) + ' capa ' + [IO.Path]::GetFileNameWithoutExtension((Limpar (Split-Path $p -Leaf))) + $ext)
        Add $p $d (Acao $p $d) 'capa' '' $x.Cliente '' $tam
    } else {
        $relSemGenericos = $x.Rel
        $d = Join-Path $pastaC ("Projeto\" + $relSemGenericos); Add $p $d (Acao $p $d) 'projeto' '' $x.Cliente '' $tam
    }
}

# ---------------------------------------------------------------- pastas vazias
foreach ($v in "$($C)Varandagem", "$($C)Nova pasta", "$($S)Desktop\Backup 2024", "$($S)Desktop\Adobe", "$($S)Program Files", "$($S)WindowsApps") { Add $v '' 'REMOVER_SE_VAZIA' 'vazia' '' '' '' 0 }

# ---------------------------------------------------------------- conflitos de destino no plano
$dup = $plano | Where-Object destino | Group-Object { $_.destino.ToLower() } | Where-Object Count -gt 1
foreach ($g in $dup) { foreach ($x in $g.Group) { $x.observacao = ($x.observacao + ' CONFLITO NO PLANO').Trim() } }

$csv = Join-Path $base 'plano.csv'
$plano | Select-Object origem, destino, acao, tipo, observacao, cliente, conteudo, tamanho | ConvertTo-Csv -Delimiter ';' -NoTypeInformation | Set-Content -LiteralPath $csv -Encoding UTF8
"plano: $($plano.Count) linhas -> $csv"
"nao mapeados: $($naoMapeados.Count)"; $naoMapeados | Select-Object -First 40
"conflitos no plano: $(@($dup).Count)"
