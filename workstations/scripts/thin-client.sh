#!/usr/bin/env bash
# lpklarkc kiosk. Wi-Fi -> trusted USB -> Google IAP -> RDP.
# A full desktop is not installed; Ctrl+Alt+F2 remains for recovery.
set -uo pipefail

STATE="${LPKLARKC_STATE_TOOL:-/run/current-system/sw/bin/lpklarkc-state}"
IAP="${LPKLARKC_IAP_TOOL:-/run/current-system/sw/bin/lpklarkc-iap}"
NM_ONLINE="${LPKLARKC_NM_ONLINE_BIN:-nm-online}"
NMCLI="${LPKLARKC_NMCLI_BIN:-nmcli}"
IP_CMD="${LPKLARKC_IP_BIN:-ip}"
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
  "$NMCLI" -t -f TYPE,STATE device status 2>/dev/null |
    grep -Eq '^(wifi|ethernet):connected$' || return 1
  "$IP_CMD" -4 route show default | grep -q '^default'
}

# A local IAP TCP listener does not prove that the remote XRDP service
# has booted. Request the 19-byte RDP X.224 negotiation (no credentials),
# and require a TPKT response from the actual destination.
rdp_responding() {
  local host="${1:-127.0.0.1}" port="${2:-13389}" reply
  reply="$(
    printf '\003\000\000\023\016\340\000\000\000\000\000\001\000\010\000\003\000\000\000' |
      timeout 5 nc -w 3 "$host" "$port" 2>/dev/null |
      od -An -tx1 -N2 | tr -d '[:space:]'
  )" || true
  [[ "$reply" == "0300" ]]
}

# Regression-test entrypoint; no credentials or remote service required.
if [[ "${1:-}" == "--check-network" ]]; then
  network_ready
  exit $?
fi
if [[ "${1:-}" == "--check-rdp" ]]; then
  rdp_responding "${2:-127.0.0.1}" "${3:-13389}"
  exit $?
fi

printf '\033[2J\033[H'
printf '\n  ========================================\n'
printf '              LPKLARKC\n'
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
  usb_retries=0
  while ! usb_error="$(sudo -n "$STATE" ensure 2>&1)"; do
    usb_retries=$((usb_retries + 1))
    if (( usb_retries == 1 || usb_retries % 4 == 0 )); then
      printf '\n  Unidade USB de configuracao indisponivel.\n'
      printf '  Tentando recuperar acesso ao pendrive, sem alterar o disco interno.\n'
      printf '  Diagnostico: Ctrl+Alt+F2 e execute lpklarkc-state diagnose\n'
      # Present the last precise error instead of an endless generic loop.
      printf '  %s\n' "$(printf '%s\n' "$usb_error" | tail -n1)"
    fi
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

  # Query the exact GCE resource, start once if TERMINATED, wait for
  # RUNNING, and only then establish IAP. Retry IAM/billing failures safely.
  if ! "$IAP" ensure-running; then
    printf '\n  Nao foi possivel ligar ou consultar a workstation.\n'
    printf '  Confira permissoes GCE, cobranca e rede. Tentando novamente...\n'
    if network_ready && ! "$IAP" check; then
      printf '  Sessao Google expirada; autorizacao necessaria.\n'
      "$IAP" login || true
    fi
    sleep 30
    continue
  fi

  printf '\n  Conectando ao seu computador remoto...\n'
  TUNNEL_LOG="$(mktemp)"
  "$IAP" tunnel >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!

  ready=false
  # Cold boots enter RUNNING before XRDP is listening. Wait for a true
  # RDP response through IAP instead of merely a local TCP listener.
  for ((attempt = 0; attempt < 90; attempt++)); do
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then break; fi
    if grep -qF 'Listening on port [13389]' "$TUNNEL_LOG" &&
       rdp_responding; then
      ready=true
      break
    fi
    sleep 2
  done

  if [[ "$ready" == true ]]; then
    printf '  XRDP respondendo. Abrindo area de trabalho...\n'
    # xfreerdp is X11-based. Start a rootless Xorg session directly from
    # tty1, with no LightDM/Openbox/Xterm. When RDP exits, Xorg terminates
    # and the console immediately resumes the retry loop.
    startx "$(command -v xfreerdp)" /v:"$RDP_ADDRESS" /f \
      /dynamic-resolution /cert:tofu /clipboard /network:auto /sec:tls \
      /sound:sys:pulse /microphone:sys:pulse \
      -- :0 vt1 -keeptty -nolisten tcp || true
    printf '\n  Sessao encerrada. Reconectando...\n'
  else
    printf '\n  Nao foi possivel conectar ao servidor.\n'
    printf '  Verifique XRDP, IAM e o tunel IAP.\n'
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
