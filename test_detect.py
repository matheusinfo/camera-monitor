"""Confere a detecção contra os alertas rotulados no histórico.

No /historico cada visita pode ser marcada como alerta certo ou falso alarme
(fica em fotos/rotulos.json). Este teste usa esses rótulos de dois jeitos:

  1. filtros (sempre): reaplica os filtros de hoje (server.descartar) nas
     caixas que o detector gravou no eventos.jsonl na hora do alerta. Não
     depende do modelo nem da recompressão do JPEG: o resultado é sempre o
     mesmo. Use ao mexer em PESSOA_MIN, PESSOA_BASE_MIN e afins.
  2. modelo (--modelo): roda o detector de hoje de novo nas fotos. A foto é
     JPEG recomprimido e não reproduz o ao vivo à risca; serve para comparar
     modelos e limiares.

Falha se algum alerta certo deixar de alertar. Falso alarme barrado é contado,
não exigido.

Com as fotos da Echo:
  mkdir -p /tmp/echo && ssh echo 'tar -C /data/camera-monitor -cf - fotos' | tar -C /tmp/echo -xf -
  python3 test_detect.py /tmp/echo/fotos --modelo
"""
import argparse
import contextlib
import io
import os
import sys

# o server.py exige a câmera no ambiente, mas aqui ela não é usada; e liga a
# detecção de veículo, para os alertas de carro parado também contarem
for chave in ("CAM_HOST", "CAM_USER", "CAM_PASS"):
    os.environ.setdefault(chave, "teste")
os.environ.setdefault("CARRO_PARADO_S", "20")

import cv2  # noqa: E402

import server  # noqa: E402


def categoria(foto):
    return foto.rsplit("_", 1)[1][:-4]


def resumo(nome, alertou):
    """alertou: foto -> (rótulo, ainda alerta?). Devolve as certas perdidas."""
    certos = [f for f, (r, _) in alertou.items() if r == "real"]
    falsos = [f for f, (r, _) in alertou.items() if r == "falso"]
    perdidos = [f for f in certos if not alertou[f][1]]
    barrados = [f for f in falsos if not alertou[f][1]]
    print(f"{nome}: {len(certos)} certos, {len(certos) - len(perdidos)} ainda alertam; "
          f"{len(falsos)} falsos, {len(barrados)} barrados")
    for f in perdidos:
        print(f"  PERDEU alerta certo: {f}")
    return perdidos


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("pasta", nargs="?", default=server.FOTOS_DIR,
                    help="pasta com as fotos, eventos.jsonl e rotulos.json (padrão: fotos)")
    ap.add_argument("--modelo", action="store_true",
                    help="também roda o detector de novo nas fotos rotuladas")
    args = ap.parse_args()

    rotulos = server.ler_rotulos(os.path.join(args.pasta, "rotulos.json"))
    if not rotulos:
        sys.exit(f"nenhum alerta rotulado em {args.pasta}/rotulos.json: marque no /historico")
    eventos = {ev["photo"]: ev
               for ev in server.ler_eventos(os.path.join(args.pasta, "eventos.jsonl")) or []
               if ev.get("photo")}

    filtros, sem_caixas = {}, 0
    for foto, rotulo in sorted(rotulos.items()):
        ev = eventos.get(foto)
        if not ev or "dets" not in ev:
            sem_caixas += 1     # alerta de antes de 2026-11-06: só a foto
            continue
        W, H = ev.get("quadro") or (cv2.imread(os.path.join(args.pasta, foto)).shape[1::-1])
        cat = categoria(foto)
        filtros[foto] = (rotulo, any(
            d["category"] == cat
            and server.descartar(cat, d["confidence"], d["box"], W, H, H) is None
            for d in ev["dets"]))
    perdidos = resumo("filtros (caixas gravadas)", filtros)
    if sem_caixas:
        print(f"  {sem_caixas} rotulados sem caixas gravadas (de antes de 06/11): só no --modelo")

    if args.modelo:
        modelo = {}
        for foto, rotulo in sorted(rotulos.items()):
            img = cv2.imread(os.path.join(args.pasta, foto))
            if img is None:
                continue
            cat = categoria(foto)
            with contextlib.redirect_stdout(io.StringIO()):   # o log de cada caixa
                dets = server.detect(img)
            modelo[foto] = (rotulo, any(d["category"] == cat for d in dets))
        perdidos += resumo("modelo (fotos de novo)", modelo)

    if perdidos:
        sys.exit(1)


if __name__ == "__main__":
    main()
