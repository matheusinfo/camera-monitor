#!/bin/sh
# Roda NA Echo Show (techo5), em /data/camera-monitor. Monta a imagem base de
# 64 bits do camera-monitor (ffmpeg, MediaMTX, numpy/opencv do PyPI):
#   sh echo-deps.sh
# So precisa rodar de novo quando mudar requirements-docker.txt ou o MediaMTX.
#
# Por que 64 bits e por que assim:
# - O Docker da Echo e armhf, mas o kernel e aarch64. O OpenCV do Debian armhf
#   vem sem NEON: o MobileNet levava ~3,9 s por analise. O wheel aarch64 do PyPI
#   (NEON) leva ~0,7 s com 1 thread e ~0,4 s com 2.
# - Container arm64 morre com SIGSYS no seccomp padrao do dockerd armhf, que so
#   conhece a ABI de 32 bits. seccomp-echo.json e o perfil padrao do Docker com
#   SCMP_ARCH_AARCH64 como subarquitetura do ARM: mesmas regras nas duas ABIs.
# - O builder classico nao aceita --security-opt ("not supported on linux"),
#   entao nenhum RUN de 64 bits roda em docker build: as dependencias entram por
#   docker run + docker commit aqui, e o Dockerfile.echo so faz COPY.
# - Kernel Android (CONFIG_ANDROID_PARANOID_NETWORK): o usuario _apt nao abre
#   sockets, por isso o sandbox do apt fica como root.
set -eu
cd "$(dirname "$0")"

IMAGE=camera-monitor-deps:arm64
BASE=python:3.10-slim-bookworm
MEDIAMTX_VERSION=v1.21.1

docker pull -q --platform linux/arm64 "$BASE" >/dev/null
docker tag "$BASE" python-arm64:3.10-slim-bookworm

cid=$(docker create --security-opt seccomp="$PWD/seccomp-echo.json" \
    -v "$PWD/requirements-docker.txt:/tmp/requirements.txt:ro" \
    python-arm64:3.10-slim-bookworm sh -euc "
        apt-get -o APT::Sandbox::User=root update
        apt-get -o APT::Sandbox::User=root install -y --no-install-recommends \
            ffmpeg ca-certificates curl libglib2.0-0
        rm -rf /var/lib/apt/lists/*
        curl -fsSL https://github.com/bluenviron/mediamtx/releases/download/$MEDIAMTX_VERSION/mediamtx_${MEDIAMTX_VERSION}_linux_arm64.tar.gz \
            | tar -xz -C /usr/local/bin mediamtx
        pip install --no-cache-dir --root-user-action=ignore -r /tmp/requirements.txt
        python3 -c 'import cv2, sys; assert sys.maxsize > 2**32; print(\"opencv\", cv2.__version__, \"64 bits\")'
    ")
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker start -a "$cid"
docker commit \
    --change 'ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1' \
    --change 'CMD []' \
    "$cid" "$IMAGE" >/dev/null
echo "imagem $IMAGE pronta"
