# Changelog

## Unreleased

- `NTFY_TOKEN`: token de acesso para ntfy proprio com login (`Authorization: Bearer`). Vazio segue como antes, sem login.
- Corrigido: o FFmpeg era derrubado pelo watchdog a cada 35 min 47 s, quando a camera pula o relogio dos quadros (2^31 us). O `fps=8` despejava ~600 quadros repetidos por segundo (~20 s de CPU e o video parado a cada vez). Agora o FFmpeg usa a hora de chegada (`-use_wallclock_as_timestamps`): sem quadro B no stream, a ordem e a mesma, e o video atravessa o salto a 8 quadros/s.
- Menos CPU sem ninguem assistindo: o quadro do FFmpeg fica em I420 cru e so vira BGR quando alguem usa (o YOLOX, o MJPEG do painel, o PTZ). O filtro de movimento sai do Y, igual ao cinza do BGR em ate 1-2 niveis contra o limiar de 20: em 10 min de video da Echo, as mesmas analises nos mesmos quadros. Na Echo, no mesmo trecho de video: 4,8 -> 1,9 ms por quadro sem ninguem assistindo (3,9% -> 1,5% de um nucleo a 8 fps); com o painel aberto, 12,0 -> 11,4 ms.

- Detector trocado para o YOLOX-Tiny (Megvii, Apache-2.0, entrada 320x192), no lugar do MobileNet-SSD. Nas 300 fotos de alerta da Echo, rotuladas uma a uma: ve 273 das 284 pessoas reais (MobileNet 251) e nao gera pessoa na chuva, em quadro corrompido, nem os "onibus" falsos no portao. Custo na Echo ~1,1x (0,80 s contra 0,73 s por analise). `PESSOA_MIN` passa a 0,35 e o filtro de chuva a 0,5 no YOLOX. `DETECT_MODEL=mobilenet` volta ao antigo, que segue no Pi 3 (YOLOX nao medido la). Caminhao (picape, van) conta como veiculo.
- Um push por visita, nao um a cada 20 s: o 1o alerta abre a visita; enquanto a pessoa (ou bicho) continua aparecendo, sem sumir por mais de `VISITA_FIM_S` (90 s), entra mais uma foto a cada 20 s, sem push. Na Echo uma pessoa 12 min no portao mandou 35 pushes. O painel mostra a visita uma vez, com "+N fotos"; o historico mostra um card por visita (as fotos de antes juntam pela hora, com a mesma regra).
- Marcacao de alerta certo / falso alarme no historico (zoom, teclas `c` e `f`), em `fotos/rotulos.json`. O `test_detect.py` foi refeito em cima dela: reaplica os filtros de hoje nas caixas gravadas no `eventos.jsonl` (resultado estavel) e, com `--modelo`, roda o detector de novo nas fotos. Falha se algum alerta certo deixar de alertar. O `eventos.jsonl` passa a gravar a visita e o tamanho do quadro.
- CI roda o `_selfcheck` do `server.py` (antes so `py_compile`).
- Modo em casa no painel: sem push sempre, ou so num horario (pode virar a meia-noite); fotos e historico continuam. Os avisos de saude do video vao sempre.
- Video em HD (botao **HD**): o stream principal em HLS, copiado pelo MediaMTX sem decodificar, repassado pelo app com o login do painel. Caixas da deteccao num canvas, sincronizadas pelo `PROGRAM-DATE-TIME`. Precisa de navegador com H.265 (Chrome/Edge com hardware, Safari); sem isso o botao fica apagado. Enquanto o HD esta ligado o MJPEG fecha. O MediaMTX deixou de abrir RTMP, SRT e WebRTC, que nao eram usados.
- `HEARTBEAT_URL`: GET a cada 5 min enquanto o video chega (healthchecks.io e afins). Se o aparelho cair, o servico de fora avisa.
- `/healthz` diz o estado do video (`ok`, `aguardando vídeo`, `sem vídeo há N s`), sempre com 200.
- Pedidos que mudam algo (`POST`/`PUT`/`DELETE` e `/test`) vindos de outro site sao recusados (`Sec-Fetch-Site`/`Origin`): uma pagina maliciosa aberta por quem esta logado nao vira mais a camera.
- `deploy-echo.sh`: atualiza a Echo mandando so os arquivos que mudaram, remonta a imagem base quando precisa e confere o `server.py` no container, o icone e o video. Guarda os arquivos substituidos em `.deploy-anterior/`.
- `compose.echo.yaml` com o DNS fixo que so existia na Echo (apos queda de energia o app ficava sem DNS e o painel em 403).

- Foto e push do alerta saem limpos, sem a caixa e a porcentagem por cima da pessoa; o video ao vivo continua marcado. A caixa e a confianca de cada alerta ficam em `fotos/eventos.jsonl`, que nao e mais cortado ao reiniciar (o painel segue com os 10 mais recentes).
- Painel mostra so os 10 alertas mais recentes. Todas as fotos ficam na nova pagina `/historico` (botao **Historico**): agrupadas por dia, com filtro por dia e por tipo e zoom com setas. A lista sai da pasta `fotos/`, entao inclui as fotos que ja tinham saido do painel.
- Titulo do painel mostra onde o monitor roda pela variavel `PAINEL_LOCAL` (`Echo Show` na Echo); antes era sempre "Raspberry Pi".
- Menos alerta falso de pessoa: quem passa de moto ou carro na rua, visto pela grade, nao avisa mais (caixa com a base acima de `PESSOA_BASE_MIN`, 70% da altura). Chuva na lente, que virava uma caixa do topo ao pe do quadro, so avisa com confianca de 0,6 ou mais. O log mostra o motivo do descarte.
- Adicionado icone na aba do navegador (`/favicon.svg`, tambem em `/favicon.ico`): camera em SVG, dentro do `server.py`, sem pedir login.
- Adicionado alerta de carro parado (`CARRO_PARADO_S`): avisa uma vez quando um veiculo fica esse tempo no mesmo lugar, em qualquer ponto da imagem (garagem, rampa, rua); carro que so passa muda de lugar e nao avisa. O mesmo carro so avisa de novo depois de 5 min sem ser visto ali. Caixa de veiculo do quadro quase inteiro e descartada (pessoa colada na camera saia "onibus 0,68").
- Corrigido: o historico de alertas sumia do painel ao reiniciar o container ou a Echo. Agora fica em `fotos/eventos.jsonl`, com data no horario.
- Adicionado `DETECT_TILES`: analisa recortes do quadro para achar pessoa pequena ou atras de grade.
- Foto e push do alerta usam o quadro analisado, nao o mais novo (em CPU lenta a caixa ficava no vazio).
- Corrigido `/test`: o push de teste agora leva a foto.
- Push no ntfy quando o video para por 1 min, quando volta, e quando o watchdog reinicia o FFmpeg 3+ vezes em 10 min.
- Container do Pi em `America/Sao_Paulo`: hora das notificacoes e nome das fotos saiam em UTC (3 h a frente).
- Watchdog tambem reinicia o FFmpeg com mais de 64 KB parados no socket: atrasado, o lado dele seguia ESTABLISHED e o painel travava.
- `VIDEO_FPS` (4 no Pi): metade do custo de conversao, JPEG e envio.
- Sem ninguem no `/stream`, a captura nao gera JPEG (so a foto do alerta).
- Filtro de movimento ignora chuva: exige mancha continua de `MOTION_BLOB` px (substitui `MOTION_MIN`). Na chuva o MobileNet rodava sem parar.
- Watchdog reinicia o FFmpeg quando o MediaMTX derruba a conexao dele (antes o painel ficava minutos em video velho).
- `/stream` so envia quadro novo: mandava 12,5 JPEG/s para 8 quadros/s, carga a mais no cloudflared do Pi.
- Limiar de pessoa 0,65 -> 0,25 (`PESSOA_MIN`): atras da grade do portao a confianca fica em 0,25-0,45; no video do entregador, de 7% para 66% dos quadros detectados.
- Pessoa notifica na 1a analise (animal continua em 3 seguidas): no Pi cada analise leva ~4,5 s e quem parava poucos segundos no portao nao gerava alerta. Pessoas detectadas e quase-detectadas (0,4 a 0,65) vao para o log.
- PTZ mais rapido: sem o `Stop` e sem a espera de 3 s; segurar a seta anda sem parar.
- Adicionadas posicoes salvas da camera (`/posicoes`), com ajuste final pela imagem.
- Deteccao so roda quando a cena muda (`MOTION_MIN`), com analise forcada a cada 10 s.
- FFmpeg entrega quadros crus (YUV4MPEG) em vez de MJPEG: ~3x menos CPU no Pi 3.
- Adicionado deploy automatico no Raspberry Pi a cada push na `main` (job `deploy-pi`).
- Corrigido o CI: `Validate Compose` falhava sem `.env` no runner.
- Adicionado deploy no Raspberry Pi 3 (`Dockerfile.pi`, `compose.pi.yaml`), sem PC ligado.
- Adicionado push no celular via ntfy, com foto do alerta e link para o ao vivo.
- Deteccao passou a rodar em thread propria: o video nao trava durante a analise.
- Adicionados `DETECT_THREADS` e `DETECT_INTERVAL_S` para ajustar o custo de CPU.
- Adicionado `CAM_AUDIO_PATH` para puxar o audio de outro caminho quando o substream nao tem audio.
- Corrigido: falha de audio no relay derrubava o video.
- Gunicorn com 8 threads: varios espectadores nao travam o painel.
- Removido do Git o certificado autoassinado gerado pelo MediaMTX (`auto.crt`/`auto.key`).
- Adicionada documentacao visual e guia completo de operacao.
- Adicionado CI para Python, shell, Compose e build Docker.
- Adicionado Gunicorn para servir a aplicacao em container.
- Fixada a imagem do Cloudflare Tunnel.
- Adicionado movimento PTZ vertical para cima e para baixo.
- Adicionada autenticacao HTTP Basic no painel.
