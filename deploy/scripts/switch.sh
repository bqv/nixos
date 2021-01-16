#!@shell@
#!@execline@/bin/execlineb -Ws0

# TODO: Reboot automatically if kernel update?
# TODO: Take some things from auto-upgrade.nix

# Have a remote command, with usage:
# switch start <system> -> <id>
# switch active <id> -> success | failure | unknown, exit code 0 when done, 1
#   when not done, reports that we can connect to the host
# switch run -> does the actual switch, should be run asynchronously via systemd

# We store state like this:
# @systemSwitcherDir@
#   /next: <n>
#   /current -> system-<n> (optional)
#   /system-<n>
#     /system -> /nix/store/xxx
#     /status: success | failure | unknown
#     /confirm: (socket, optional)
#     /active: 0 | 1
#     /fifo: Pipe where output is piped to
#     /log: File where logs are recorded

set -u

# This script needs to be run as root
if [[ "$EUID" -ne 0 ]]; then
        exec @privilegeEscalationCommand@ "$0" "$@"
fi

mkdir -p @systemSwitcherDir@
chmod 770 @systemSwitcherDir@
cd @systemSwitcherDir@

switch-start() {
  local system=$1
  if ! [ -x "$system/bin/switch-to-configuration" ]; then
    echo "$system doesn't appear to be a NixOS system" >&2
    exit 1
  fi

  local id
  if [ -f next ]; then
    id=$(cat next)
  else
    id=0
  fi

  local current="system-$id"
  if ! ln -sT "system-$id" current; then
    echo "Switch $(readlink current) is already in progress" >&2
    exit 1
  fi

  echo $(( id + 1 )) > next
  mkdir "$current"
  ln -sT "$system" current/system
  echo unknown > current/status
  echo 1 > current/active

  nohup "$0" run >>"$current/log" 2>&1 &

  echo "$id"
}

switch-active() {
  local id=$1
  cat "system-$id/status"
  local active=$(cat "system-$id/active")
  # Could also wait for updates after the ping
  if [ -p "system-$id/confirm" ]; then
    echo PING > "system-$id/confirm"
  fi
  exit "$active"
}


waitConfirm() {
  mkfifo current/confirm
  echo "Waiting for confirmation.." >&2
  read -t @successTimeout@ -r <>current/confirm
  confirmed=$?
  rm current/confirm
  return $confirmed
}

switch() {
  local system=$1
  local action=$2
  timeout --foreground @switchTimeout@ "$system/bin/switch-to-configuration" "$action"
  local code=$?
  if [ $code -eq 124 ]; then
    echo "Activation of $system timed out" >&2
    return $code
  elif [ $code -ne 0 ]; then
    if [ "@ignoreFailingSystemdUnits@" = 1 ] && [ $code -eq 4 ]; then
      echo "During activation of $system, some systemd units failed to activate" >&2
      return 0
    else
      echo "Activation of $system failed" >&2
      return $code
    fi
  fi
}

fail() {
  echo failure > current/status
  if [ "@rollbackOnFailure@" != 1 ]; then
      exit 1
  fi
  echo "Rolling back.." >&2
  switch "$1" switch

  waitConfirm
  code=$?

  echo 0 > current/active
  rm current

  if [ "$code" -ne 0 ]; then
    echo "Unsuccessfully rolled back without rebooting" >&2
    echo "Rebooting to rollback.." >&2
    @panicAction@
  fi

  echo "Successfully rolled back without rebooting" >&2
  exit 1
}

switch-run() {
  mkfifo current/fifo
  exec 3> current/fifo
  exec 1>&3

  if [ ! -d current ]; then
    echo "No system to activate" >&2
    exit 1
  fi

  local newsystem=$(realpath current/system)
  local oldsystem=$(realpath /run/current-system)

  if switch "$newsystem" test; then
    echo "Activated new system successfully"
    if waitConfirm; then
      echo "Success confirmation received, activating system" >&2
      if switch "$newsystem" boot; then
        nix build --profile /nix/var/nix/profiles/system --no-link "$newsystem"
        # We need to run the boot switch again for the new system to be
        # available in the boot loader since it uses the system profiles to
        # generate that
        # TODO: I feel like there should be a better way
        switch "$newsystem" boot
        echo success > current/status
        echo 0 > current/active
        rm current/fifo
        rm current
      else
        echo "Failed to boot switch" >&2
        fail "$oldsystem"
      fi
    else
      echo "Success confirmation not received in time" >&2
      fail "$oldsystem"
    fi
  else
    echo "System activation failed" >&2
    fail "$oldsystem"
  fi
}

case "$1" in
  "start")
    switch-start "$2"
    ;;
  "active")
    switch-active "$2"
    ;;
  "run")
    switch-run
    ;;
  *)
    echo "No such command $1" >&2
    ;;
esac
