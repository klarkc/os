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
OAUTH_SESSION="${LPKLARKC_OAUTH_SESSION_TOOL:-/run/current-system/sw/bin/lpklarkc-oauth-session}"
STARTX="${LPKLARKC_STARTX_BIN:-startx}"
LOGINCTL="${LPKLARKC_LOGINCTL_BIN:-loginctl}"
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
  # The watchdog starts only after XRDP initially answers, and then
  # independently validates consecutive final GCE states.
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

# The real Dell has i915 on /dev/dri/card1; naming and firmware alone
# cannot prove logind's DRM lease is active. Avoid launching Xorg when
# logind EXPLICITLY reports an inactive tty1 session or another VT.
# A failed/unavailable read remains diagnostic-only, not a hard kiosk lock.
xorg_tty1_seat_ready() {
  local snapshot active="" vtnr="" key value seen_active=0 seen_vtnr=0
  if ! snapshot="$("$LOGINCTL" show-session self --property=Active --property=VTNr --no-pager 2>/dev/null)"; then
    echo "Aviso: estado logind indisponivel; tentando Xorg sem inferir DRM ativo." >&2
    return 0
  fi
  while IFS='=' read -r key value; do
    case "$key" in
      Active)
        if (( seen_active )); then
          echo "Xorg adiado: logind retornou Active duplicado." >&2
          return 1
        fi
        active="$value"
        seen_active=1
        ;;
      VTNr)
        if (( seen_vtnr )); then
          echo "Xorg adiado: logind retornou VTNr duplicado." >&2
          return 1
        fi
        vtnr="$value"
        seen_vtnr=1
        ;;
    esac
  done <<< "$snapshot"
  if [[ "$active" == "no" ]]; then
    echo "Xorg adiado: logind relata sessao tty1 inativa (DRM pode estar pausado)." >&2
    return 1
  fi
  if [[ "$active" != "yes" ]]; then
    echo "Xorg adiado: logind nao confirmou Active=yes para tty1." >&2
    return 1
  fi
  if [[ -n "$vtnr" && "$vtnr" != "1" ]]; then
    printf 'Xorg adiado: sessao logind esta em VT %s, esperado tty1.\n' "$vtnr" >&2
    return 1
  fi
  if [[ "$vtnr" != "1" ]]; then
    echo "Xorg adiado: logind nao confirmou VTNr=1." >&2
    return 1
  fi
  return 0
}


# One-command, read-only field evidence. A tty2 snapshot is NOT proof of
# logind/DRM ownership at the moment the rootless Xorg :0 session started.
diagnose_xorg() {
  local drm_dir="${LPKLARKC_DIAG_DRM_DIR:-/dev/dri}"
  local sys_drm_dir="${LPKLARKC_DIAG_SYS_DRM_DIR:-/sys/class/drm}"
  local log="${LPKLARKC_DIAG_XORG_LOG:-${HOME:-/home/nixos}/.local/share/xorg/Xorg.0.log}"
  local node card major_minor driver_path driver excerpt found=0
  printf 'Diagnostico Xorg/DRM (somente leitura, estado atual)\n'
  local self_snapshot="" seat_snapshot="" session_id="" active_session=""
  local property value seat_candidate
  printf 'Sessao logind deste comando (pode ser tty2, nao o momento da falha):\n'
  if self_snapshot="$("$LOGINCTL" show-session self --property=Id --property=Active --property=VTNr --no-pager 2>/dev/null)"; then
    printf '%s\n' "$self_snapshot"
    while IFS='=' read -r property value; do
      if [[ "$property" == "Id" && "$value" =~ ^[[:alnum:]_-]+$ ]]; then
        session_id="$value"
      fi
    done <<< "$self_snapshot"
  else
    printf '  consulta logind indisponivel\n'
  fi
  printf 'Sessao ativa em seat0 (estado atual):\n'
  if seat_snapshot="$("$LOGINCTL" show-seat seat0 --property=ActiveSession --no-pager 2>/dev/null)"; then
    printf '%s\n' "$seat_snapshot"
    while IFS='=' read -r property value; do
      seat_candidate="${value%% *}"
      if [[ "$property" == "ActiveSession" && "$seat_candidate" =~ ^[[:alnum:]_-]+$ ]]; then
        active_session="$seat_candidate"
      fi
    done <<< "$seat_snapshot"
  else
    printf '  consulta seat0 indisponivel\n'
  fi
  # Compare only snapshots from this command. From tty2, a different
  # session can be normal and says nothing about an earlier tty1 Xorg FD.
  if [[ -z "$session_id" || -z "$active_session" ]]; then
    printf 'Correlacao self/seat0: INDETERMINADA (consulta incompleta)\n'
  elif [[ "$session_id" == "$active_session" ]]; then
    printf 'Correlacao self/seat0: MESMA_SESSAO (instante da consulta)\n'
  else
    printf 'Correlacao self/seat0: DIVERGENTE (instante da consulta; tty2 pode ser esperado)\n'
  fi
  printf 'DRM cardN e driver kernel:\n'
  for node in "$drm_dir"/card[0-9]*; do
    [[ -e "$node" ]] || continue
    card="${node##*/}"
    [[ "$card" =~ ^card[0-9]+$ ]] || continue
    major_minor="$(cat "$sys_drm_dir/$card/dev" 2>/dev/null)" || major_minor="?"
    driver_path="$(readlink -f "$sys_drm_dir/$card/device/driver" 2>/dev/null)" || driver_path=""
    driver="${driver_path##*/}"
    [[ -n "$driver" ]] || driver="?"
    printf '  %s major_minor=%s driver=%s\n' "$card" "$major_minor" "$driver"
    found=1
  done
  (( found )) || printf '  nenhum cardN presente\n'
  printf 'Assinaturas relevantes do Xorg.0.log:\n'
  if [[ -r "$log" ]]; then
    excerpt="$(grep -Ei 'xfree86: Adding drm device|systemd-logind: got fd for /dev/dri/card|Error systemd-logind returned paused fd|open /dev/dri/card[0-9]+: No such file or directory|Screen 0 deleted|Device\(s\) detected, but none match|no screens found|Server terminated with error' "$log" | tail -n 18)" || true
    if [[ -n "$excerpt" ]]; then
      printf '%s\n' "$excerpt"
    else
      printf '  sem assinaturas Xorg/DRM selecionadas\n'
    fi
  else
    printf '  Xorg.0.log indisponivel neste usuario\n'
  fi
  printf 'Observacao: estado atual nao prova a sessao no instante em que Xorg abriu DRM.\n'
}

# A separate rootless Xorg session hosts Firefox only during Google OAuth.
# Xorg returns to tty1 before the normal full-screen FreeRDP session starts.
local_oauth_login() {
  if ! "$SUDO" -n "$STATE" is-ready; then
    echo "USB Ventoy nao validado para OAuth (ou permissao sudo is-ready ausente)." >&2
    echo "Diagnostico no tty2: lpklarkc-state diagnose" >&2
    return 5
  fi
  if [[ ! -x "$OAUTH_SESSION" ]] || ! command -v "$STARTX" >/dev/null 2>&1; then
    echo "Navegador OAuth local ou startx ausente da ISO." >&2
    return 4
  fi
  if ! xorg_tty1_seat_ready; then
    echo "Retorne ao tty1 antes de iniciar o navegador grafico." >&2
    return 7
  fi
  echo "Iniciando Firefox temporario no Dell para autenticar Google..."
  if ! "$STARTX" "$OAUTH_SESSION" -- :0 vt1 -keeptty -nolisten tcp; then
    echo "OAuth local cancelado/erro de navegador. Corrija a causa e tente novamente." >&2
    return 1
  fi
  if ! "$IAP" check; then
    echo "OAuth local nao produziu token Google utilizavel; USB nao foi considerada autenticada." >&2
    return 1
  fi
  return 0
}

# Regression-test entrypoints; injected IAP reads only, never writes GCE.
if [[ "${1:-}" == "--check-xorg-seat" ]]; then
  xorg_tty1_seat_ready
  exit $?
fi

if [[ "${1:-}" == "--diagnose-xorg" ]]; then
  diagnose_xorg
  exit $?
fi

if [[ "${1:-}" == "--check-network" ]]; then
  network_ready
  exit $?
fi
if [[ "${1:-}" == "--check-rdp" ]]; then
  rdp_responding "${2:-127.0.0.1}" "${3:-13389}"
  exit $?
fi
if [[ "${1:-}" == "--check-peer-stopped" ]]; then
  peer_stopped
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
      # The watchdog never powers off due to network loss; only repeated,
      # matching GCE SUSPENDED/TERMINATED responses permit local shutdown.
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
  while ! usb_error="$("$SUDO" -n "$STATE" ensure 2>&1)"; do
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
  "$SUDO" -n "$STATE" save >/dev/null 2>&1 || true

  if ! "$IAP" has-credentials; then
    printf '\n  Autorizacao inicial da conta Google necessaria.\n'
    printf '  Siga as instrucoes exibidas a seguir.\n\n'
    if ! local_oauth_login; then
      printf '\n  Login Google incompleto; confirme USB, navegador e autenticacao.\n'
      printf '  Ctrl+Alt+F2 abre o diagnostico. Nova tentativa em 20 segundos.\n'
      sleep 20
      continue
    fi
  fi

  # Only one resume phase per Dell boot; never auto-start TERMINATED or
  # compete with a safe server-side suspend after the first connection.
  if [[ "$WAKE_COMPLETED" == false ]]; then
    if ! "$IAP" ensure-running; then
      printf '\n  Nao foi possivel ligar ou consultar a workstation.\n'
      printf '  Confira status, permissao resume, cota e rede. Sem start automatico.\n'
      if network_ready && ! "$IAP" check; then
        printf '  Sessao Google expirada; autorizacao necessaria.\n'
        local_oauth_login || true
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
    if xorg_tty1_seat_ready; then
      startx "$(command -v xfreerdp)" /v:"$RDP_ADDRESS" /f \
      /dynamic-resolution /cert:tofu /clipboard /network:auto /sec:tls \
      /sound:sys:pulse /microphone:sys:pulse \
      -- :0 vt1 -keeptty -nolisten tcp || true
    else
      echo "Xorg/RDP adiado ate tty1 voltar a ficar ativo." >&2
    fi
    printf '\n  Sessao encerrada. Reconectando...\n'
  else
    printf '\n  Nao foi possivel conectar ao servidor.\n'
    printf '  Verifique XRDP, IAM e o tunel IAP.\n'
    if network_ready && ! "$IAP" check; then
      printf '  Sessao Google expirada; autorizacao necessaria.\n'
      local_oauth_login || true
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
