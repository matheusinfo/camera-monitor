#!/bin/sh
# Atualiza o camera-monitor na Echo Show (techo5). Da raiz do projeto:
#   ./deploy-echo.sh
# Manda so os arquivos que mudaram (compara o sha256 daqui com o de la),
# rebuilda e confere: o server.py dentro do container e este, o icone responde
# sem login e o video chega. Sem nada mudado, so confere.
#
# - ECHO_HOST troca o host do ssh (padrao: "echo", do ~/.ssh/config; entra como root).
# - Quando requirements-docker.txt ou echo-deps.sh mudam, remonta antes a imagem
#   base (echo-deps.sh, alguns minutos).
# - O .env nao vai: ele fica so na Echo (chmod 600).
# - Os arquivos substituidos ficam em /data/camera-monitor/.deploy-anterior/:
#   para voltar, copie de la para a pasta e rode o compose up de novo.
set -eu
cd "$(dirname "$0")"

HOST=${ECHO_HOST:-echo}
DIR=/data/camera-monitor
COMPOSE="docker compose -f compose.echo.yaml --profile tunnel"
# O que o Dockerfile.echo copia, mais o que monta a imagem e o tunnel.
ARQUIVOS="server.py config.py ptz.py gunicorn.conf.py docker-entrypoint.sh
  yolox_tiny.onnx MobileNetSSD_deploy.prototxt MobileNetSSD_deploy.caffemodel
  Dockerfile.echo Dockerfile.cloudflared compose.echo.yaml echo-deps.sh
  seccomp-echo.json requirements-docker.txt"
BASE="requirements-docker.txt echo-deps.sh"

ssh "$HOST" "test -f $DIR/.env" || {
    echo "falta $DIR/.env na Echo: copie a parte, uma vez (chmod 600)" >&2
    exit 1
}

remoto=$(ssh "$HOST" "cd $DIR && sha256sum $(echo $ARQUIVOS) 2>/dev/null" || true)
mudou=
for f in $ARQUIVOS; do
    h=$(sha256sum "$f" | cut -d' ' -f1)
    printf '%s\n' "$remoto" | grep -qxF "$h  $f" || mudou="$mudou $f"
done

if [ -z "$mudou" ]; then
    echo "nada mudou: so conferindo"
else
    echo "mandando:$mudou"
    ssh "$HOST" "cd $DIR && rm -rf .deploy-anterior && mkdir .deploy-anterior \
        && for f in $mudou; do [ ! -e \$f ] || cp -p \$f .deploy-anterior/; done"
    # shellcheck disable=SC2086
    tar -czf - $mudou | ssh "$HOST" "mkdir -p $DIR/fotos && tar -C $DIR -xzf - \
        && chown -R 10002:10002 $DIR/fotos"
    for f in $BASE; do
        case " $mudou " in
            *" $f "*)
                echo "imagem base mudou: rodando o echo-deps.sh (alguns minutos)"
                ssh "$HOST" "cd $DIR && sh echo-deps.sh"
                break ;;
        esac
    done
    ssh "$HOST" "cd $DIR && $COMPOSE up -d --build"
fi

esperado=$(sha256sum server.py | cut -d' ' -f1)
confere() {
    ssh "$HOST" "cd $DIR && $COMPOSE exec -T camera-monitor python3 -" 2>/dev/null <<'PY'
import hashlib, urllib.request as u
h = hashlib.sha256(open("/app/server.py", "rb").read()).hexdigest()
icone = u.urlopen("http://127.0.0.1:8090/favicon.svg", timeout=5)
assert icone.status == 200 and b"<svg" in icone.read()
print(h, u.urlopen("http://127.0.0.1:8090/healthz", timeout=5).read().decode())
PY
}

estado="o app nao respondeu"
for _ in $(seq 36); do        # ate ~3 min: o MediaMTX e o video demoram a subir
    if saida=$(confere); then
        if [ "${saida%% *}" != "$esperado" ]; then
            echo "ERRO: o server.py no container nao e o daqui" >&2
            exit 1
        fi
        estado=${saida#* }
        if [ "$estado" = ok ]; then
            echo "ok: server.py novo no ar, icone responde sem login, video chegando"
            exit 0
        fi
    fi
    sleep 5
done
echo "ERRO: depois de 3 min, $estado. Ultimas linhas do log:" >&2
ssh "$HOST" "cd $DIR && $COMPOSE logs --tail 30 camera-monitor" >&2
exit 1
