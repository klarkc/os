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
WATCHDOG="${LPKLARKC_WATCHDOG_TOOL:-/run/current-system/sw/bin/lpklarkc-peer-watchdog}"
POWEROFF="${LPKLARKC_POWEROFF_TOOL:-/run/current-system/sw/bin/lpklarkc-poweroff}"
SUDO="${LPKLARKC_SUDO_BIN:-sudo}"
TUNNEL_PID=""
TUNNEL_LOG=""
WATCHDOG_PID=""
WAKE_COMPLETED=false
RDP_READY_ONCE=false
# The Dell never auto-suspends/hibernates. It powers off normally only when
# remote suspension/termination has been confirmed; server work is preserved.

stop_tunnel() {
  if [[ -n "$TUNNEL_PID" ]]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  [[ -z "$TUNNEL_LOG" ]] || rm -f -- "$TUNNEL_LOG"
  TUNNEL_PID=""
  TUNNEL_LOG=""
}

cleanup() {
  stop_tunnel
  if [[ -n "$WATCHDOG_PID" ]]; then
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

request_local_shutdown() {
  printf '\n  Encerrando o Dell: a workstation remota nao esta mais disponivel.\n'
  if ! "$SUDO" -n "$POWEROFF"; then
    echo "Falha ao solicitar desligamento local; tente pelo console." >&2
    return 1
  fi
  # The immutable privileged wrapper invokes systemctl poweroff --no-block.
  # Do not reenter the auto-start loop while the machine is shutting down.
  exit 0
}

peer_stopped() {
  local status
  # Failure to consult GCE is NOT proof that the VM has stopped.
  # The independent watchdog also checks the actual XRDP response.
  status="$(timeout 15 "$IAP" instance-status 2>/dev/null)" || return 1
  case "$status" in
    TERMINATED|SUSPENDED)
      # The server controller owns safe suspend. Ignore transitional states
      # and confirm the *final* state twice before powering off locally.
      local confirmation
      sleep 3
      confirmation="$(timeout 15 "$IAP" instance-status 2>/dev/null)" || return 1
      [[ "$confirmation" == "$status" ]] || return 1
      printf '  Workstation confirmou estado %s.\n' "$status"
      return 0
      ;;
  esac
  return 1
}

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
  if [[ "$WAKE_COMPLETED" == true ]] && peer_stopped; then
    request_local_shutdown || sleep 5
    continue
  fi
  while ! network_ready; do
    if [[ "$RDP_READY_ONCE" == true ]]; then
      # Once paired, do not wait indefinitely in an interactive nmtui.
      # The watchdog powers off after a sustained peer/network outage.
      printf '\n  Rede indisponivel; aguardando reconexao automatica...\n'
      sleep 5
      continue
    fi
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

  # Only one resume phase per Dell boot; never auto-start TERMINATED or
  # compete with a safe server-side suspend after the first connection.
  if [[ "$WAKE_COMPLETED" == false ]]; then
    if ! "$IAP" ensure-running; then
      printf '\n  Nao foi possivel ligar ou consultar a workstation.\n'
      printf '  Confira status, permissao resume, cota e rede. Sem start automatico.\n'
      if network_ready && ! "$IAP" check; then
        printf '  Sessao Google expirada; autorizacao necessaria.\n'
        "$IAP" login || true
      fi
      sleep 30
      continue
    fi
    WAKE_COMPLETED=true
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
    RDP_READY_ONCE=true
    if [[ -z "$WATCHDOG_PID" ]] || ! kill -0 "$WATCHDOG_PID" 2>/dev/null; then
      # The watchdog stays alive across FreeRDP reconnections, so a hung
      # FreeRDP client cannot keep the local Dell powered indefinitely.
      "$WATCHDOG" &
      WATCHDOG_PID=$!
    fi
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

  stop_tunnel
  # If GCE stopped while FreeRDP was connected, shut down locally.
  # Otherwise attempt reconnect without issuing any second VM start.
  if [[ "$WAKE_COMPLETED" == true ]] && peer_stopped; then
    request_local_shutdown || sleep 5
  fi
  sleep 5
done
