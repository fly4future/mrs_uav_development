# get the path to this script

PNAME=$( ps -p "$$" -o comm= )
SNAME=$( echo "$SHELL" | grep -Eo '[^/]+/?$' )

if [ "$SNAME" = "bash" ]; then
  MY_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
else
  MY_PATH=`dirname "$0"`
  MY_PATH=`( cd "$MY_PATH" && pwd )`
fi

REPO_PATH=$MY_PATH/../

# disable gitman caching
export GITMAN_CACHE_DISABLE=1

# #{ sourceShellDotfile()

getRcFile() {

  case "$PNAME" in
    bash)
      RCFILE="$HOME/.bashrc"
      ;;
    zsh)
      RCFILE="$HOME/.zshrc"
      ;;
  esac

  echo "$RCFILE"
}

sourceShellDotfile() {

  RCFILE=$( getRcFile )

  source "$RCFILE"
}

# #}
alias sb="sourceShellDotfile"

## --------------------------------------------------------------
## |                       MRS simulation                       |
## --------------------------------------------------------------

# #{ bash completion function definition
function _spawn_uav_bash_complete()
{
  local arg opts
  COMPREPLY=()
  arg="${COMP_WORDS[COMP_CWORD]}"
  opts=`rosrun mrs_simulation spawn --help | grep '  --' | awk '{print $1}'`
  COMPREPLY=( $(compgen -W "${opts}" -- ${arg}) )
}
# #}

# #{ zsh completion function definition
function _spawn_uav_zsh_complete()
{
  local opts
  reply=()
  opts=`rosrun mrs_simulation spawn --help | grep '  --' | awk '{print $1}'`
  reply=(${=opts})
}
# #}

# selection of specific function for different shells
case "$PNAME" in
  bash)
    complete -f "_spawn_uav_bash_complete" "spawn_uav"
    ;;
  zsh)
    compctl -k "_spawn_uav_zsh_complete" "spawn_uav"
    ;;
esac

## --------------------------------------------------------------
## |                             Git                            |
## --------------------------------------------------------------

# #{ git2https()

git2https() {

  old_remote=$(git remote get-url origin)
  echo Old remote: $old_remote

  new_remote=$(echo $old_remote | sed -r 's|.*git@(.+):(.+)|https://\1/\2|' | head -n 1)
  echo New remote: $new_remote

  if [ -n "$new_remote" ]; then
    git remote set-url origin "$new_remote"
  fi
}

# #}

# #{ git2ssh()

git2ssh() {

  old_remote=$(git remote get-url origin)
  echo Old remote: $old_remote

  new_remote=$(echo $old_remote | sed -r 's|https://([^/]+)/(.+)|git@\1:\2|' | head -n 1)
  echo New remote: $new_remote

  if [ -n "$new_remote" ]; then
    git remote set-url origin "$new_remote"
  fi
}

# #}

# #{ gitUpdateSubmodules()

gitUpdateSubmodules() {

  echo "Syncing git submodules"
  command git submodule sync
  echo "Updating git submodules"
  command git submodule update --init --recursive

  if [ -f .gitman.yml ]; then
    if [[ ! $(git status .gitman.yml --porcelain) ]]; then # if .gitman.yml is unchanged
      echo "Updating gitman sub-repos"
      gitman install
    else
      echo -e "\e[31m.gitman.yml modified, not updating sub-repos\e[0m"
    fi
  fi
}

# #}

# #{ git()

# upgrades the "git pull" to allow dotfiles profiling on linux-setup
# Other "git" features should not be changed
git() {

  case $* in

    push*)

      was_github=$(command git remote get-url origin | grep 'https://github.com' | wc -l)

      # change remote to ssh
      [ "$was_github" -ge 1 ] && git2ssh

      # run the original command
      command git "$@"
      ;;

    pull*|checkout*|"reset --hard")

      # give me the path to root of the repo we are in
      ROOT_DIR=`git rev-parse --show-toplevel` 2> /dev/null

      # we are in git repo subfolder
      if [[ "$?" == "0" ]]; then

        # if we are in the 'linux-setup' repo, use the Profile manager
        if [[ "$ROOT_DIR" == "$GIT_PATH/linux-setup" ]]; then

          PROFILE_MANAGER="$GIT_PATH/linux-setup/submodules/profile_manager/profile_manager.sh"

          bash -c "$PROFILE_MANAGER backup $GIT_PATH/linux-setup/appconfig/profile_manager/file_list.txt"

          command git "$@"

          if [[ "$?" == "0" ]]; then
            case $* in
              pull*|checkout*) # TODO: should only work for checkout of a branch
                gitUpdateSubmodules
                ;;
            esac
          fi

          if [[ "$?" == "0" ]]; then
            bash -c "$PROFILE_MANAGER deploy $GIT_PATH/linux-setup/appconfig/profile_manager/file_list.txt"
          fi

        # this is generic git repo subfolder
        else

          command git "$@"

          if [[ "$?" == "0" ]]; then
            case $* in
              pull*|checkout*) # TODO: should only work for checkout of a branch
                gitUpdateSubmodules
                ;;
            esac
          fi

        fi

      # we are not aware of being in a git subfolder
      else

        # lets run the command as it would originally would
        command git "$@"

        # and if it somehow succeeds, just update the submodules
        if [[ "$?" == "0" ]]; then
          case $* in
            pull*|checkout*) # TODO: should only work for checkout of a branch
              gitUpdateSubmodules
              ;;
          esac
        fi
      fi
      ;;
    *)
      command git "$@"
    ;;

  esac
}

# #}

# #{ gdb

gdba() {

  NODE_NAME=$1

  PID=""

  while true; do

    PID=$(ps aux | grep -e "$NODE_NAME" | vims -e "grep" "dd" | vims -s "^dWElD" | head -n 1)

    if [[ $PID != " " ]]; then
      break
    fi

    echo "waiting for '$NODE_NAME' to start"

    sleep 1

  done

  gdb attach $PID -ex c
}

# #}

alias gs="git status"
alias gcmp="git checkout master; git pull"
alias flog="~/.scripts/git-forest.sh --all --date=relative --abbrev-commit --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --style=15"
alias glog="git log --graph --abbrev-commit --date=relative --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'"

## --------------------------------------------------------------
## |                             ROS                            |
## --------------------------------------------------------------

export RCUTILS_COLORIZED_OUTPUT=1

# #{ presource_ros()

export ROS_PRESOURCE_PATH=/tmp/ros_presource_output.sh

# version of the cache's format: a cache written in an older format is regenerated even when the workspace's packages did not change
ROS_PRESOURCE_FORMAT=1

# fingerprint of the packages that sourcing the workspace sets up: colcon's setup finds them by their package index files,
# install/<pkg>/share/colcon-core/packages/<pkg> (or install/share/colcon-core/packages/<pkg> with --merge-install);
# a glob instead of find, since every new shell runs it, and in a subshell, so the glob and locale settings stay local
ros_workspace_fingerprint() {
  (
    [ -n "$ZSH_VERSION" ] && setopt null_glob
    # a locale-independent order of the glob, otherwise shells with different locales would keep regenerating each other's cache
    LC_ALL=C
    _presource_fingerprint="$ROS_PRESOURCE_FORMAT"
    for _presource_index in "$ROS_WORKSPACE"/install/*/share/colcon-core/packages/* "$ROS_WORKSPACE"/install/share/colcon-core/packages/*; do
      [ -e "$_presource_index" ] && _presource_fingerprint="$_presource_fingerprint ${_presource_index##*/}"
    done
    printf '%s' "$_presource_fingerprint"
  )
}

presource_ros() {

  if [ -z $ROS_WORKSPACE ]; then
    return 0
  fi

  if [ ! -d ${ROS_WORKSPACE}/install ]; then
    echo "[presource_ros()]: \$ROS_WORKSPACE/install does not exist (\$ROS_WORKSPACE = $ROS_WORKSPACE)."
  fi

  # per-process temp file so concurrent shells can't race on $ROS_PRESOURCE_PATH
  local ROS_PRESOURCE_TMP
  if ! ROS_PRESOURCE_TMP=$(mktemp "${ROS_PRESOURCE_PATH}.XXXXXX"); then
    echo "[presource_ros()]: ERROR: cannot create a temporary file next to $ROS_PRESOURCE_PATH, the workspace was not presourced"
    return 1
  fi

  # taken before sourcing: a package installed in the meantime then makes the next shell presource again,
  # instead of being missing from a cache that claims to include it
  local ROS_PRESOURCE_FINGERPRINT=$(ros_workspace_fingerprint)

  # subshell: reset + sourcing stay local to it, nothing to clean up afterward
  (
    # only these two are unambiguously ROS-only; others may carry non-ROS content
    unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH

    source /opt/ros/jazzy/setup.$SNAME > /dev/null 2>&1
    [ -f $ROS_WORKSPACE/install/setup.$SNAME ] && source $ROS_WORKSPACE/install/setup.$SNAME > /dev/null 2>&1

    # snapshot final values -- COLCON_TRACE output skips vars whose value looks like a duplicate
    for _presource_var in AMENT_PREFIX_PATH CMAKE_PREFIX_PATH COLCON_PREFIX_PATH \
                           LD_LIBRARY_PATH PATH PYTHONPATH \
                           GAZEBO_MODEL_PATH GAZEBO_RESOURCE_PATH IGN_GAZEBO_MODEL_PATH IGN_GAZEBO_RESOURCE_PATH \
                           GZ_CONFIG_PATH GZ_SIM_RESOURCE_PATH GZ_SIM_SYSTEM_PLUGIN_PATH \
                           ROS_DISTRO ROS_VERSION ROS_PYTHON_VERSION ROS_AUTOMATIC_DISCOVERY_RANGE; do
      eval "_presource_val=\$$_presource_var"
      # escape for safe re-sourcing
      _presource_val=$(printf '%s' "$_presource_val" | sed 's/[\\"$`]/\\&/g')
      printf '%s\n' "export $_presource_var=\"$_presource_val\""
    done
  ) > $ROS_PRESOURCE_TMP

  # add the fingerprint and our marker so we can recognize from which workspace, and which of its packages, does this originate
  echo "# fingerprint $ROS_PRESOURCE_FINGERPRINT" >> $ROS_PRESOURCE_TMP
  echo "# $ROS_WORKSPACE" >> $ROS_PRESOURCE_TMP

  mv $ROS_PRESOURCE_TMP $ROS_PRESOURCE_PATH

  echo "[presource_ros()]: colcon workspace '$ROS_WORKSPACE' was presourced"

  # apply to this shell (the sourcing above only happened in the subshell)
  source $ROS_PRESOURCE_PATH
}

if [ -z "$NIX_ENV_ROOT" ]; then

  if [ -z "$ROS_WORKSPACE" ]; then

    source /opt/ros/jazzy/setup.$SNAME

  else

    # (re)generate the cache in a subshell, whether this shell sources it is decided below
    if [ ! -f "$ROS_PRESOURCE_PATH" ]; then
      ( presource_ros )
    # check if the workspace changed
    elif [ "$(tail -n 1 "$ROS_PRESOURCE_PATH")" != "# $ROS_WORKSPACE" ]; then
      echo "[presource_ros()]: colcon workspace changed"
      ( presource_ros )
    # check if the workspace's packages changed, e.g. by a build that bypassed colcon() below
    elif ! grep -q -x -F "# fingerprint $(ros_workspace_fingerprint)" "$ROS_PRESOURCE_PATH"; then
      echo "[presource_ros()]: packages of the colcon workspace changed"
      ( presource_ros )
    fi

    # the shell that only starts tmux does not need the environment, the shells inside tmux source it themselves
    if [ -f "$ROS_PRESOURCE_PATH" ] && { [ -z "$RUN_TMUX" ] || ! $RUN_TMUX || [ -n "$TMUX" ]; }; then
      source "$ROS_PRESOURCE_PATH"
    fi
  fi

fi

# #}

# #{ colcon()

colcon() {

  CURRENT_PATH=`pwd`

  case $* in

    init*)

      if [ ! -f "build/COLCON_IGNORE" ]; then
        mkdir -p build src
        touch build/COLCON_IGNORE

        if [ ! -f "colcon_defaults.yaml" ]; then
          cat <<EOT > colcon_defaults.yaml
build:
  symlink-install: true
  mixin:
    - rel-with-deb-info
    - compile-commands
  allow-overriding: []
EOT
        fi
      fi

      ;;

    build*)

      # go up the folder tree until we find the build/COLCON_IGNORE file or until we reach the root
      while [ ! -f "build/COLCON_IGNORE" ]; do
        cd ..
        if [[ `pwd` == "/" ]]; then
          # we reached the root and didn't find the build/COLCON_IGNORE file - that's a fail!
          echo "Cannot compile, probably not in a workspace (if you want to create a new workspace, call \"colcon init\" in its root first)".
          cd "$CURRENT_PATH" # return to the path where this command was originaly called
          return 1
        fi
      done

      if [ -n "$ROS_WORKSPACE" ] && [[ $(pwd) != $(eval echo "$ROS_WORKSPACE") ]]; then

        echo "Cannot compile, you are compiling a different workspace than you are sourcing. This will corrupt your workspace with unwanted dependency."
        echo "If you actually want to build dependent workspaces, unset the ROS_WORKSPACE variable and source the workspaces directly."
        return 1
      fi

      if [ ! -f "colcon_defaults.yaml" ]; then
        echo -e "\e[1;33m[!] WARNING: 'colcon_defaults.yaml' not found in $(pwd).\e[0m"
        echo -e "\e[33m    Proceeding with standard system defaults for this build.\e[0m"
      fi

      # fingerprint the installed packages, to detect below whether the build added or removed one
      BEFORE_PKGS=$(ros_workspace_fingerprint)

      # if the flow got here, we found the build/COLCON_IGNORE file!
      # this is the folder we're looking for - call the actual colcon command here
      command colcon "$@" --symlink-install
      ret=$? # remember the return value of the colcon command

      # only re-presource (costly) if the package set actually changed; a rebuild of an
      # existing package doesn't affect AMENT_PREFIX_PATH & co.; also after a failed build,
      # since the packages that finished before the failure are installed
      AFTER_PKGS=$(ros_workspace_fingerprint)
      if [ "$BEFORE_PKGS" != "$AFTER_PKGS" ]; then
        presource_ros
      fi

      cd "$CURRENT_PATH" # return to the path where this command was originaly called

      return $ret # return the original return value of the colcon command

      ;;

    test*)

      # go up the folder tree until we find the build/COLCON_IGNORE file or until we reach the root
      while [ ! -f "build/COLCON_IGNORE" ]; do
        cd ..
        if [[ `pwd` == "/" ]]; then
          # we reached the root and didn't find the build/COLCON_IGNORE file - that's a fail!
          echo "Cannot run tests, probably not in a workspace (if you want to create a new workspace, call \"colcon init\" in its root first)".
          cd "$CURRENT_PATH" # return to the path where this command was originaly called
          return 1
        fi
      done

      # if the flow got here, we found the build/COLCON_IGNORE file!
      # this is the folder we're looking for - call the actual colcon command here
      command colcon "$@"
      ret=$? # remember the return value of the colcon command
      cd "$CURRENT_PATH" # return to the path where this command was originaly called
      return $ret # return the original return value of the colcon command

      ;;

    clean*)

      if [ -f "build/COLCON_IGNORE" ]; then # we are at the workspace root
        rm -r build install log
        mkdir build
        cd build
        touch COLCON_IGNORE
      else
        while [ ! -f "build/COLCON_IGNORE" ]; do
          cd ..

          if [[ `pwd` == "/" ]]; then
            echo "Cannot clean, not in a workspace!"
            break
          elif [ -f "build/COLCON_IGNORE" ]; then
            rm -r build install log
            mkdir build
            cd build
            touch COLCON_IGNORE
            break
          fi
        done
      fi

      cd "$CURRENT_PATH" # return to the original folder where the command was called

      ;;

    *)
      command colcon $@
      ;;

  esac
}

# #}

# #{ cb()

cb()  {

  colcon build "$@"
}

# #}

# #{ roscd()

roscd() {

  if [ ! -z $COLCON_PREFIX_PATH ]; then

    if [ -z $1 ]; then
      cd $COLCON_PREFIX_PATH/../src
      return 0
    fi

    # first, find the package in the sourced worksapce
    package_path=$(
      colcon list --base-paths $COLCON_PREFIX_PATH/.. 2>/dev/null | \
      grep -E "^$1\s" | awk '{print $2}'
    )

    if [ ! -z $package_path ]; then
      cd $package_path
      return 0
    fi

  fi

  if [ -z $1 ]; then
    cd /opt/ros/jazzy/share
    return 0
  fi

  # then, try to find the package within the installed packages
  package_path=$(ros2 pkg prefix --share $1 2> /dev/null)

  if [ ! -z $package_path ]; then
    cd $package_path
    return 0
  fi

  # finally, just cd into the workspace
  cd $COLCON_PREFIX_PATH/../src
}

_roscd_complete() {

  local current_word
  current_word="${COMP_WORDS[COMP_CWORD]}"

  # Get the list of package names using colcon list
  local packages

  if [ ! -z $COLCON_PREFIX_PATH ]; then
    packages=$(colcon list --base-paths $COLCON_PREFIX_PATH/.. 2>/dev/null | awk '{print $1}')
  fi

  packages="$packages
  $(ros2 pkg list)"

  # reply=(${=packages})
  COMPREPLY=($(compgen -W "$packages" -- "$current_word"))
}

complete -F _roscd_complete roscd

# #}

# #{ cd()

SYMLINK_ARRAY_PATH="/tmp/ros_workspace_link_database.sh"

# generate the symlink list
# if we are not in TMUX
if [ -z $TMUX ]; then

  # and the symlinklist does not exist
  if [ ! -f "$SYMLINK_ARRAY_PATH" ]; then

    # create the symlink list
    $REPO_PATH/scripts/tmux_detacher.sh $REPO_PATH/scripts/create_ros_symlink_database.sh
  fi
fi

# if the array file exists, just source it
[ -f "$SYMLINK_ARRAY_PATH" ] && source $SYMLINK_ARRAY_PATH

cd() {

  [ -z "$SYMLINK_LIST_PATHS1" ] && [ -f "$SYMLINK_ARRAY_PATH" ] && source $SYMLINK_ARRAY_PATH

  if [ -z "$SYMLINK_LIST_PATHS1" ]; then

    builtin cd "$@"
    return

    # if we have ag, do the magic
  else

    builtin cd "$@"
    new_path=`pwd`

    # test original paths for prefix

    case "$PNAME" in
      bash)
        fucking_shell_offset="0"
        ;;
      zsh)
        fucking_shell_offset="1"
        ;;
    esac

    # echo ""
    j="1"

    for ((i=$fucking_shell_offset; i < ${#SYMLINK_LIST_PATHS1[*]}+$fucking_shell_offset; i++));
    do

      temp=${SYMLINK_LIST_PATHS2[$i]}

      if [[ $new_path == *$temp* ]]
      then

        # echo "found prefix: ${SYMLINK_LIST_PATHS1[$i]} -> $temp for $new_path"
        # echo substracted: ${new_path#*$temp}
        repath[$j]="${SYMLINK_LIST_PATHS1[$i]}${new_path#*$temp}"
        # echo new_path: ${repath[$j]}
        new_path=${repath[$j]}
        j=$(expr $j + 1)
        # echo ""

      fi

    done

    if [ "$j" -ge "2" ]
    then
      builtin cd "$new_path"
    fi
  fi
}

CURRENT_PATH=`pwd`
cd "$CURRENT_PATH"

# #}

eval "$(/usr/bin/register-python-argcomplete ros2)"
eval "$(/usr/bin/register-python-argcomplete colcon)"

## --------------------------------------------------------------
## |                           Docker                           |
## --------------------------------------------------------------

# #{ dk() 

dk() {
  # Get all container IDs first to avoid race conditions.
  local cids
  cids=$(docker ps -a -q)

  if [[ "$PNAME" == 'zsh' ]]; then
    cids=(${=cids})
  fi

  # Stop and remove all containers if they exist.
  if [[ -n "$cids" ]]; then
    echo "Stopping and removing all containers..."
    # The '-f' flag force-stops and removes running containers in one go.
    # Errors are shown by default for better debugging.
    docker rm -f $cids
    echo "Containers removed."
  else
    echo "No containers to remove."
  fi

  # Ask separately to prune volumes.
  local volume_response
  # This printf/read pattern is compatible with both Bash and Zsh.
  printf "Prune unused volumes? (y/N) "
  read -r volume_response
  case "$volume_response" in
    [yY] | [yY][eE][sS])
      echo "Pruning unused volumes..."
      docker volume prune -f
      ;;
    *)
      echo "Skipping volume prune."
      ;;
  esac

  # Ask separately to prune networks.
  local network_response
  printf "Prune unused networks? (y/N) "
  read -r network_response
  case "$network_response" in
    [yY] | [yY][eE][sS])
      echo "Pruning unused networks..."
      docker network prune -f
      ;;
    *)
      echo "Skipping network prune."
      ;;
  esac
}

# #}
