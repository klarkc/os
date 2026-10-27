#!/usr/bin/env bash
# Solo Workstation kiosk. Wi-Fi -> trusted USB -> Google IAP -> RDP.
# A full desktop is not installed; Ctrl+Alt+F2 remains for recovery.
set -uo pipefail

STATE="${SOLO_STATE_TOOL:-/run/current-system/sw/bin/solo-client-state}"
IAP="${SOLO_IAP_TOOL:-/run/current-system/sw/bin/solo-gce-iap}"
NM_ONLINE="${SOLO_NM_ONLINE_BIN:-nm-online}"
RDP_ADDRESS="127.0.0.1:13389"
TUNNEL_PID=""
TUNNEL_LOG=""

cleanup() {
  if [[ -n "$TUNNEL_PID" ]]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  [[ -z "$TUNNEL_LOG" ]] || rm -f -- "$TUNNEL_LOG"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# A Wi-Fi connection manually activated using nmtui can already have a valid
# route while nm-online is still timing out. Verify NM link and IPv4 route.
network_ready() {
  "$NM_ONLINE" -q -t 6 && return 0
  nmcli -t -f TYPE,STATE device status 2>/dev/null |
    grep -Eq '^(wifi|ethernet):connected$' || return 1
  ip -4 route show default | grep -q '^default'
}

# Regression-test entrypoint; no credentials or remote service required.
if [[ "${1:-}" == "--check-network" ]]; then
  network_ready
  exit $?
fi

printf '\033[2J\033[H'
printf '\n  ========================================\n'
printf '              SOLO WORKSTATION\n'
printf '  ========================================\n\n'
printf '  Iniciando seu ambiente de trabalho remoto.\n\n'

while true; do
  while ! network_ready; do
    printf '\n  Conecte-se a uma rede Wi-Fi.\n'
    printf '  O configurador sera aberto agora.\n\n'
    nmtui || true
    sleep 2
  done

  # A boot-time Ventoy mount failure must be recoverable after live boot.
  # 'ensure' re-discovers the USB and/or VentoyPart on every retry.
  while ! sudo -n "$STATE" ensure >/dev/null 2>&1; do
    printf '\n  Unidade USB de configuracao indisponivel.\n'
    printf '  Mantenha o pendrive conectado. Tentando novamente.\n'
    printf '  Diagnostico avancado: Ctrl+Alt+F2\n'
    sleep 6
  done
  sudo -n "$STATE" save >/dev/null 2>&1 || true

  if ! "$IAP" has-credentials; then
    printf '\n  Autorizacao inicial da conta Google necessaria.\n'
    printf '  Siga as instrucoes exibidas a seguir.\n\n'
    until "$IAP" login; do
      printf '\n  Autorizacao incompleta. Verifique sua rede.\n'
      sleep 8
    done
  fi

  printf '\n  Conectando ao seu computador remoto...\n'
  TUNNEL_LOG="$(mktemp)"
  "$IAP" tunnel >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!

  ready=false
  for ((attempt = 0; attempt < 65; attempt++)); do
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then break; fi
    if grep -qF 'Listening on port [13389]' "$TUNNEL_LOG" &&
       nc -z -w 1 127.0.0.1 13389 2>/dev/null; then
      ready=true
      break
    fi
    sleep 1
  done

  if [[ "$ready" == true ]]; then
    printf '  Conexao pronta. Abrindo area de trabalho...\n'
    xfreerdp /v:"$RDP_ADDRESS" /f /dynamic-resolution \
      /cert:tofu /clipboard /network:auto /sec:tls || true
    printf '\n  Sessao encerrada. Reconectando...\n'
  else
    printf '\n  Nao foi possivel conectar ao servidor.\n'
    printf '  Confira se a workstation esta ligada e o IAP foi liberado.\n'
    if network_ready && ! "$IAP" check; then
      printf '  Sessao Google expirada; autorizacao necessaria.\n'
      "$IAP" login || true
    fi
  fi

  cleanup
  TUNNEL_PID=""
  TUNNEL_LOG=""
  sleep 5
done
