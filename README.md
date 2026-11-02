# Camera Monitor

> Monitoramento RTSP com deteccao de pessoas e animais, audio da camera, alertas e controle PTZ em uma interface web protegida.

![Camera Monitor](docs/preview.svg)

[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![MediaMTX](https://img.shields.io/badge/RTSP-MediaMTX-111827)](https://github.com/bluenviron/mediamtx)
[![CI](https://github.com/plugato/camera-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/plugato/camera-monitor/actions/workflows/ci.yml)

> **Fork** de [plugato/camera-monitor](https://github.com/plugato/camera-monitor), o
> projeto principal. Este fork acrescenta o deploy numa
> [Echo Show 5 com techo5](#rodando-numa-echo-show-5-techo5) e o historico de
> alertas persistente; o resto acompanha o upstream.

**Documentacao:** [seguranca](SECURITY.md) · [como contribuir](CONTRIBUTING.md) · [changelog](CHANGELOG.md)

O Camera Monitor transforma o stream RTSP da camera em um painel web pratico para acompanhar a cena, ouvir o audio, receber notificacoes e mover uma camera PTZ.

## O que ele faz

- Recebe video H.265 e audio G.711 da camera via RTSP.
- Usa MediaMTX como relay para lidar com a negociacao RTSP da camera.
- Converte o video para MJPEG e analisa os frames com MobileNet-SSD.
- Detecta pessoas e animais com limiar de confianca configuravel no codigo.
- Desenha as deteccoes no stream e registra fotos dos alertas.
- Envia notificacoes desktop no Linux e no Windows.
- Envia push para o celular (app ntfy) com a foto do alerta e link para o ao vivo.
- Reproduz o audio da camera pelo navegador.
- Controla o eixo horizontal e vertical da camera via ONVIF/PTZ.
- Protege o painel com usuario e senha HTTP Basic.
- Pode publicar o painel por um Cloudflare Tunnel dentro do Docker.
- Roda sozinho num Raspberry Pi 3 na rede da camera, sem PC ligado.
- Roda numa Echo Show 5 com techo5 (Debian armhf com Docker), tambem sem PC ligado.

## Arquitetura

```mermaid
flowchart LR
    C[Camera RTSP\nH.265 + G.711] --> M[MediaMTX\nrelay UDP]
    M --> F[FFmpeg\nMJPEG + PCM]
    F --> P[Python Flask\nOpenCV + MobileNet-SSD]
    P --> B[Navegador\nvideo, audio, alertas e PTZ]
    P --> T[Cloudflare Tunnel\nacesso remoto HTTPS]
    P --> O[ONVIF\nmovimento PTZ]
    P --> N[ntfy\npush no celular]
```

O fluxo principal fica dentro de um container. O MediaMTX e o monitor Python compartilham a rede interna do container; o Cloudflare Tunnel fica em um container separado e publica apenas a porta web do monitor.

## Requisitos

- Docker Engine
- Docker Compose v2
- Uma camera RTSP com ONVIF para PTZ
- Credenciais RTSP e ONVIF da camera
- Token de execucao de um Cloudflare Tunnel, caso o acesso remoto seja necessario

## Configuracao

Crie o arquivo de ambiente:

```bash
cp .env.exemplo .env
```

Preencha os valores:

```env
CAM_HOST=192.168.1.100
CAM_USER=usuario_rtsp
CAM_PASS=senha_rtsp
CAM_RTSP_PORT=554
CAM_ONVIF_PORT=5000
CAM_PATH=onvif1

APP_USER=admin
APP_PASS=use-uma-senha-longa-e-unica

CLOUDFLARE_TUNNEL_TOKEN=token-do-tunel
```

Variaveis opcionais:

| Variavel | Padrao | Para que serve |
| --- | --- | --- |
| `CAM_AUDIO_PATH` | vazio | Caminho da camera de onde puxar o audio, quando `CAM_PATH` nao tem audio (ex.: `onvif2` + `onvif1`) |
| `NTFY_URL` | vazio | Topico ntfy para push no celular. Vazio desliga o push |
| `PUBLIC_URL` | vazio | Endereco publico do painel; tocar na notificacao abre o ao vivo |
| `DETECT_THREADS` | `0` (todas) | Threads do OpenCV na deteccao |
| `DETECT_INTERVAL_S` | `0.4` | Pausa minima entre duas analises |
| `VIDEO_FPS` | `8` | Quadros/s entregues pelo FFmpeg (4 no Pi); menos = menos CPU no video, sem afetar a deteccao |
| `MOTION_BLOB` | `40` | Maior mancha de movimento (px, miniatura 160x90) para rodar o MobileNet; ignora chuva; `0` analisa sempre |
| `DETECT_TILES` | `0` | `1` tambem analisa recortes do quadro: acha pessoa pequena ou atras de grade, com ~13x mais CPU. Mantenha `0` no Pi |
| `PESSOA_MIN` | `0.25` | Confianca minima para alerta de pessoa |
| `CARRO_PARADO_S` | vazio | Segundos com um carro parado no mesmo lugar, em qualquer ponto da imagem, ate avisar (ex.: `20`). Carro que so passa nao avisa. Vazio ou `0` desliga |
| `CARRO_MIN` | `0.5` | Confianca minima para contar um veiculo |
| `WINDOWS_HOST` | vazio | So para WSL2, com `compose.wsl.yaml` |

O arquivo `.env` e ignorado pelo Git. Nunca coloque credenciais diretamente em `compose.yaml`, no codigo ou em commits.

## Executar

Suba toda a stack:

```bash
./start.sh
```

Ou use o Compose diretamente:

```bash
docker compose up -d --build
docker compose ps
```

Painel local:

```text
http://localhost:8090
```

### Rodando em WSL2

No Linux nativo o comando acima basta. Em WSL2 nao: a camera so entrega RTP por
UDP e o NAT do Windows nao devolve esse trafego para dentro da WSL. O handshake
RTSP passa, a midia nunca chega, e o painel fica em `connected: false`.

A saida e deixar o MediaMTX no host Windows, que enxerga a camera na mesma
sub-rede, e fazer o container consumir o relay dele por TCP. Baixe o
`mediamtx.exe` (build `windows_amd64`) na raiz do projeto e, em um terminal do
Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-mediamtx-windows.ps1
```

Defina `WINDOWS_HOST` no `.env` com o IP do host Windows visto pela WSL:

```bash
ip route | awk '/default/{print $3}'
```

E suba o container com o overlay:

```bash
docker compose -f compose.yaml -f compose.wsl.yaml up -d --build
```

### Rodando num Raspberry Pi

E o modo de producao: o Pi fica na mesma rede da camera, entao o RTP/UDP chega
direto e nenhum PC precisa ficar ligado. Testado num Raspberry Pi 3 Model B
(1 GB, Raspberry Pi OS 32 bits).

- `Dockerfile.pi` usa o OpenCV e o numpy do Debian: o PyPI nao tem wheel para
  armv7 e compilar num Pi 3 leva horas.
- `compose.pi.yaml` e standalone (nao e overlay) e publica o painel na porta
  `8091`. Na rede local entra direto com `APP_USER`/`APP_PASS`; de fora, pelo
  `cloudflared` do proprio Pi, com o login do Cloudflare Access.
- O Pi 3 nao decodifica o H.265 1080p em tempo real (so decodificar ja fica em
  0,97x). Use o substream: `CAM_PATH=onvif2` (640x360). Ele nao tem audio, entao
  `CAM_AUDIO_PATH=onvif1`: o MediaMTX puxa o audio do stream principal so
  enquanto alguem escuta.
- Uma analise do MobileNet-SSD custa ~2,5 s no Pi 3. A deteccao roda em thread
  propria sobre o frame mais recente, entao o video nao trava, e so quando a
  cena muda (`MOTION_BLOB`; parada, analisa a cada 10 s mesmo assim).
- O FFmpeg entrega quadros crus (YUV4MPEG) em vez de MJPEG: no Pi 3 isso caiu
  de 66% para 21% de um nucleo.
- Sem dissipador o Pi 3 chega a ~83 C e o firmware reduz o clock
  (`vcgencmd get_throttled` diferente de `0x0`). Use dissipador com cooler.

`.env` do Pi, alem das credenciais:

```env
CAM_PATH=onvif2
CAM_AUDIO_PATH=onvif1
DETECT_THREADS=2
DETECT_INTERVAL_S=2
NTFY_URL=https://ntfy.sh/<topico-secreto>
PUBLIC_URL=https://camera.seudominio.com/
```

Copiar so o necessario e subir (a partir da raiz do projeto):

```bash
tar -czf - Dockerfile.pi compose.pi.yaml server.py config.py ptz.py gunicorn.conf.py \
    docker-entrypoint.sh MobileNetSSD_deploy.prototxt MobileNetSSD_deploy.caffemodel \
  | ssh pi@ssh-pi 'mkdir -p ~/camera-monitor/fotos && tar -C ~/camera-monitor -xzf -'
ssh pi@ssh-pi 'cd ~/camera-monitor && docker compose -f compose.pi.yaml up -d --build'
```

O `.env` vai a parte, uma vez (`chmod 600` no Pi). O primeiro build leva ~7 min
no Pi 3; os seguintes so trocam a camada do codigo.

No painel do Cloudflare Tunnel do Pi, publique o hostname com servico `HTTP` e
URL `localhost:8091`. Para SSH pelo mesmo tunnel, use um hostname com servico
`SSH` e URL `localhost:22`, e no `~/.ssh/config` da sua maquina:

```text
Host ssh-pi
    HostName ssh-pi.seudominio.com
    ProxyCommand cloudflared access ssh --hostname %h
```

#### Deploy automatico pelo GitHub

Todo push na `main` com o CI verde roda o job `deploy-pi` (`.github/workflows/ci.yml`):
ele entra no Pi pelo Cloudflare Tunnel e manda os arquivos do app por SSH. No Pi
a chave de deploy tem **comando forcado** (`deploy-pi.sh`): so consegue extrair
os arquivos e rodar `docker compose up --build --wait`, sem shell.

Configuracao, uma vez:

1. Chave de deploy: `ssh-keygen -t ed25519 -N "" -C github-deploy-camera -f ~/.ssh/camera_deploy`
2. No Pi, o script e a chave restrita:

   ```bash
   ssh pi@ssh-pi 'mkdir -p ~/bin && cat > ~/bin/camera-deploy && chmod 755 ~/bin/camera-deploy' < deploy-pi.sh
   printf 'command="/home/pi/bin/camera-deploy",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding %s\n' \
     "$(cat ~/.ssh/camera_deploy.pub)" | ssh pi@ssh-pi 'cat >> ~/.ssh/authorized_keys'
   ```

3. Cloudflare Zero Trust: **Access > Service Auth > Service Tokens > Create**, e na
   aplicacao do `ssh-pi` uma policy com acao **Service Auth** incluindo esse token.
4. GitHub, **Settings > Secrets and variables > Actions**:

   | Secret | Valor |
   | --- | --- |
   | `PI_SSH_KEY` | conteudo de `~/.ssh/camera_deploy` (a privada) |
   | `PI_SSH_HOST` | `ssh-pi.seudominio.com` |
   | `PI_KNOWN_HOSTS` | chave do host: `ssh pi@ssh-pi cat /etc/ssh/ssh_host_ed25519_key.pub` (so `tipo chave`) |
   | `CF_ACCESS_CLIENT_ID` | Client ID do service token |
   | `CF_ACCESS_CLIENT_SECRET` | Client Secret do service token |

O `.env` do Pi fica no secret `PI_ENV_FILE` (conteudo inteiro do arquivo) e vai junto em cada deploy, com permissao 600: se o cartao SD morrer, um deploy recria tudo. Com o secret vazio o deploy nao mexe no `.env` que ja esta no Pi. Para mudar uma variavel, edite o secret (o GitHub nao deixa ler de volta: guarde uma copia num gerenciador de senhas) e rode o deploy de novo (Actions > CI > Run workflow).

A aplicacao exige `APP_USER` e `APP_PASS`, ou, atras do Cloudflare Access, `CF_ACCESS_TEAM` e `CF_ACCESS_AUD`: ai vale so o login do Access (o JWT de cada requisicao e validado) e nao ha segunda senha. O endpoint `/healthz` fica disponivel apenas para o healthcheck interno do Docker.

### Rodando numa Echo Show 5 (techo5)

Alternativa ao Pi: a Echo Show 5 (2a geracao, 2021) desbloqueada, com o techo5
dando um userland Debian com Docker. Tudo roda no aparelho, em
`/data/camera-monitor` (a raiz e somente leitura; `/data` sobrevive a
reiniciar).

O que muda em relacao ao Pi:

- **64 bits sobre Docker 32 bits.** O kernel e aarch64, mas o Docker e armhf. O
  OpenCV do Debian armhf vem sem NEON (~3,9 s por analise); o wheel aarch64 do
  PyPI leva ~0,7 s com 1 thread. Por isso a imagem e arm64.
- **`seccomp-echo.json`.** O perfil seccomp padrao do dockerd armhf so conhece a
  ABI de 32 bits e o container arm64 morre com `SIGSYS`. O arquivo e o perfil
  padrao do Docker com `SCMP_ARCH_AARCH64` como subarquitetura: mesmas regras
  nas duas ABIs.
- **Dependencias fora do `docker build`.** O builder classico nao aceita
  `--security-opt`, entao nenhum `RUN` de 64 bits roda no build. O
  `echo-deps.sh` monta a imagem base `camera-monitor-deps:arm64` (FFmpeg,
  MediaMTX, numpy/OpenCV) por `docker run` + `docker commit`, e o
  `Dockerfile.echo` so faz `COPY` do codigo.
- **`cloudflared` armhf.** A imagem oficial nao tem armhf: o
  `Dockerfile.cloudflared` baixa o binario armhf dos releases.
- **Rede.** O kernel Android (`CONFIG_ANDROID_PARANOID_NETWORK`) so deixa root
  ou o grupo `3003` abrir sockets: o `cloudflared` roda com `group_add: ["3003"]`
  e o apt com o sandbox como root. O firewall do techo5 recusa portas publicadas
  vindas do Wi-Fi (a menos que `DOCKER_LAN=1` em `/data/penguin/settings.conf`),
  entao a `8090` fica so no loopback e o acesso de fora e pelo tunnel.
- **CPU.** Substream `onvif2` (os A53 nao decodificam o H.265 1080p em tempo
  real) e deteccao com 1 thread a cada 0,3 s: com 2 threads o worker do OpenCV
  fica em nice 0 e o video chegou a congelar. `DETECT_TILES=1` multiplica a
  analise por ~13.
- **Persistencia.** `restart: unless-stopped` e o dockerd subindo pelo
  supervisor do techo5 trazem os containers de volta depois de reiniciar a
  Echo. Fotos e historico (`fotos/eventos.jsonl`) ficam em
  `/data/camera-monitor/fotos`.

`CAM_PATH`, `DETECT_THREADS`, `DETECT_INTERVAL_S`, `DETECT_TILES` e `TZ` ficam
no `compose.echo.yaml` e sobrepoem o `.env`. No `.env`, alem das credenciais:

```env
CAM_AUDIO_PATH=onvif1
CLOUDFLARE_TUNNEL_TOKEN=token-do-tunel
CF_ACCESS_TEAM=<team>
CF_ACCESS_AUD=<aud>
NTFY_URL=https://ntfy.sh/<topico-secreto>
PUBLIC_URL=https://camera.seudominio.com/
```

Copiar para a Echo (o SSH do techo5 entra como root; aqui com `Host echo` no
`~/.ssh/config`):

```bash
tar -czf - Dockerfile.echo Dockerfile.cloudflared compose.echo.yaml echo-deps.sh \
    seccomp-echo.json requirements-docker.txt server.py config.py ptz.py gunicorn.conf.py \
    docker-entrypoint.sh MobileNetSSD_deploy.prototxt MobileNetSSD_deploy.caffemodel \
  | ssh echo 'mkdir -p /data/camera-monitor/fotos && tar -C /data/camera-monitor -xzf -'
```

O `.env` vai a parte, uma vez (`chmod 600`). Na primeira vez, e quando mudar
`requirements-docker.txt` ou a versao do MediaMTX, monte a imagem base:

```bash
ssh echo 'cd /data/camera-monitor && sh echo-deps.sh'
```

Depois, para subir ou atualizar (o aviso de plataforma `linux/arm64/v8` contra
`linux/arm/v8` e esperado):

```bash
ssh echo 'cd /data/camera-monitor && docker compose -f compose.echo.yaml --profile tunnel up -d --build'
```

Sem o profile `tunnel` sobe so o monitor. No painel do Cloudflare Tunnel, o
hostname aponta para `HTTP` `camera-monitor:8090`, como no `compose.yaml`. O
deploy automatico do CI e so para o Pi; a Echo se atualiza com os comandos
acima.

## Cloudflare Tunnel

O servico `cloudflared` usa o token definido em `CLOUDFLARE_TUNNEL_TOKEN` e publica o destino interno `camera-monitor:8090`.

No painel da Cloudflare, associe um Public Hostname ao tunnel:

- Subdominio: `camera`
- Dominio: seu dominio Cloudflare
- Servico: `HTTP`
- URL: `camera-monitor:8090`

Para exigir uma conta ou e-mail especifico, configure tambem uma aplicacao em **Zero Trust > Access > Applications**. A autenticacao Basic da aplicacao continua sendo uma segunda camada independente.

## Notificacoes no celular

Com `NTFY_URL` definido, cada alerta vira um push no app [ntfy](https://ntfy.sh)
(Android/iOS) com a foto ja anotada, prioridade alta e, se `PUBLIC_URL` estiver
definido, toque e botao "Ao vivo" abrindo o painel. O envio roda em thread
propria: internet lenta nao segura o video.

1. Gere um topico aleatorio, por exemplo `camera-$(openssl rand -hex 8)`.
2. Coloque `NTFY_URL=https://ntfy.sh/<topico>` no `.env`.
3. No app ntfy: **+ > Subscribe to topic** com o mesmo nome.
4. Teste com `/test`.

Quem souber o nome do topico recebe as fotos: trate-o como senha. O push leva
uma foto, nao video; o ao vivo e o link.

## Controle PTZ

A interface possui quatro direcoes:

- esquerda e direita: pan
- cima e baixo: tilt

Um clique anda um passo; segurando a seta a camera continua andando (~1 passo a
cada 0,75 s).

**Posicoes salvas:** `＋ posicao` grava a posicao atual com um nome; o botao 📍
volta a ela e o `×` apaga. A camera nao informa a propria posicao, entao o
painel conta os passos e, ao chegar, corrige o resto comparando o video com uma
miniatura gravada junto (fica em `fotos/.presets/`). Se a cena mudar muito (noite
x dia), a correcao pela imagem e pulada e vale so a contagem.

O endpoint usado pela interface e:

```text
POST /ptz/<direcao>
```

Exemplo:

```bash
curl -u admin:senha -X POST http://localhost:8090/ptz/cima
```

A camera precisa aceitar o endpoint ONVIF configurado em `ptz.py`. O firmware pode limitar o tilt mesmo quando aceita o comando.

## Endpoints uteis

| Endpoint | Funcao |
| --- | --- |
| `/` | Painel web |
| `/stream` | Stream MJPEG anotado |
| `/audio` | Audio PCM da camera |
| `/status` | Estado, deteccoes e eventos |
| `/healthz` | Healthcheck interno |
| `/test` | Notificacao de teste (desktop e celular) |
| `/ptz/<direcao>` | Movimento PTZ |
| `/posicoes` | Lista as posicoes salvas |
| `/posicoes/<nome>` | `PUT` salva a atual, `POST` vai ate ela, `DELETE` apaga |
| `/fotos/<nome>` | Fotos dos alertas |

Todos os endpoints, exceto `/healthz`, exigem autenticacao Basic.

## Operacao e diagnostico

Ver logs:

```bash
docker compose logs -f camera-monitor
docker compose logs -f cloudflared
```

Verificar a camera:

```bash
docker compose ps
curl -u "$APP_USER:$APP_PASS" http://localhost:8090/status
```

Parar a stack:

```bash
docker compose down
```

Se o monitor estiver `connected: false`, confira nesta ordem:

1. Host, porta, caminho e credenciais no `.env`.
2. Alcance da camera a partir do host Docker.
3. Logs do MediaMTX no container `camera-monitor`.
4. Perdas de pacotes UDP na rede local.
5. Se a camera aceita apenas uma sessao RTSP simultanea.
6. Se o host e WSL2: veja `Rodando em WSL2`. O sintoma tipico e o MediaMTX
   reconhecer as trilhas e logo depois registrar `UDP timeout` em loop.

No Raspberry Pi:

- Logs: `ssh pi@ssh-pi 'docker compose -f ~/camera-monitor/compose.pi.yaml logs -f'`.
- Sem som com `CAM_PATH=onvif2`: falta `CAM_AUDIO_PATH=onvif1` (o substream nao
  tem trilha de audio).
- Borroes e `RTP packets lost` no log do MediaMTX: perda de UDP no Wi-Fi entre
  camera e Pi. Cabo ou Pi mais perto do roteador resolvem.
- `ssh ssh-pi` pedindo URL de login: a sessao do Cloudflare Access expirou. Rode
  `cloudflared access login ssh-pi.seudominio.com` e aumente o *Session
  Duration* da aplicacao no Zero Trust.

## Limitacoes conhecidas

- **Falar pela camera (audio bidirecional):** nao suportado. A camera (Yoosee)
  anuncia `AudioOutputs = 0` no ONVIF; o alto-falante so e acessivel pelo
  protocolo proprietario do app Yoosee.
- **Pan irregular:** cada comando anda um passo de tamanho variavel, e a direita
  anda mais que a esquerda (detalhes em `ptz.py`). Por isso as posicoes salvas
  usam a imagem para acertar o fim do caminho.
- **Sem presets na camera:** o firmware nao responde a `GetPresets`/`SetPreset`
  nem `GetStatus` do ONVIF; as posicoes salvas sao do painel.

## Testes

Validar sintaxe:

```bash
python3 -m py_compile server.py config.py ptz.py
bash -n start.sh start-mediamtx.sh
```

O teste de deteccao usa fotos de referencia privadas em `fotos/` ou `teste/`, quando disponiveis:

```bash
python3 test_detect.py
```

## Estrutura

```text
server.py                 Aplicacao Flask, stream, deteccao, audio e PTZ
ptz.py                    Cliente ONVIF para movimento da camera
Dockerfile                Imagem do monitor com FFmpeg e MediaMTX
Dockerfile.pi             Imagem para Raspberry Pi 32 bits (armv7)
Dockerfile.echo           Imagem arm64 para a Echo Show (so COPY, sobre a base do echo-deps.sh)
Dockerfile.cloudflared    cloudflared armhf para a Echo Show
compose.yaml              Monitor e Cloudflare Tunnel
compose.pi.yaml           Monitor no Raspberry Pi (standalone)
compose.echo.yaml         Monitor e tunnel na Echo Show (standalone)
compose.wsl.yaml          Overlay para WSL2, com o MediaMTX no host Windows
deploy-pi.sh              Comando forcado do deploy automatico no Pi
echo-deps.sh              Monta a imagem base arm64 na Echo Show
seccomp-echo.json         Perfil seccomp com a ABI aarch64, para o Docker armhf da Echo
docker-entrypoint.sh      Inicializa MediaMTX e o servidor Python
start-mediamtx-windows.ps1  Relay MediaMTX no host Windows, so para WSL2
.env.exemplo              Modelo de configuracao local
fotos/                    Fotos privadas dos eventos e historico (eventos.jsonl)
MobileNetSSD_deploy.*     Modelo MobileNet-SSD e configuracao Caffe
```

## Seguranca

- Mantenha `.env`, tokens Cloudflare, fotos e logs fora do Git.
- Use uma senha forte e exclusiva em `APP_PASS`.
- Prefira Cloudflare Access para restringir o dominio a usuarios autorizados.
- Revogue tokens que tenham sido compartilhados em chats, terminais ou commits antigos.
- Use um topico ntfy aleatorio: ele e a unica protecao das fotos enviadas ao celular.
