#!/usr/bin/env bash  
#
# Startup script for jetty under *nix systems (it works under NT/cygwin too).

# To get the service to restart correctly on reboot, uncomment below (3 lines):
# ========================
# chkconfig: 3 99 99
# description: Jetty 7 webserver
# processname: jetty
# ========================

# Configuration files
#
# /etc/default/jetty
#   If it exists, this is read at the start of script. It may perform any 
#   sequence of shell commands, like setting relevant environment variables.
#
# $HOME/.jettyrc
#   If it exists, this is read at the start of script. It may perform any 
#   sequence of shell commands, like setting relevant environment variables.
#
# /etc/jetty.conf
#   If found, and no configurations were given on the command line,
#   the file will be used as this script's configuration. 
#   Each line in the file may contain:
#     - A comment denoted by the pound (#) sign as first non-blank character.
#     - The path to a regular file, which will be passed to jetty as a 
#       config.xml file.
#     - The path to a directory. Each *.xml file in the directory will be
#       passed to jetty as a config.xml file.
#
#   The files will be checked for existence before being passed to jetty.
#
# $JETTY_HOME/etc/jetty.xml
#   If found, used as this script's configuration file, but only if
#   /etc/jetty.conf was not present. See above.
#   
# Configuration variables
#
# JAVA_HOME  
#   Home of Java installation. 
#
# JAVA
#   Command to invoke Java. If not set, $JAVA_HOME/bin/java will be
#   used.
#
# JAVA_OPTIONS
#   Extra options to pass to the JVM
#
# JETTY_HOME
#   Where Jetty is installed. If not set, the script will try go
#   guess it by first looking at the invocation path for the script,
#   and then by looking in standard locations as $HOME/opt/jetty
#   and /opt/jetty. The java system property "jetty.home" will be
#   set to this value for use by configure.xml files, f.e.:
#
#    <Arg><SystemProperty name="jetty.home" default="."/>/webapps/jetty.war</Arg>
#
# JETTY_PORT
#   Override the default port for Jetty servers. If not set then the
#   default value in the xml configuration file will be used. The java
#   system property "jetty.port" will be set to this value for use in
#   configure.xml files. For example, the following idiom is widely
#   used in the demo config files to respect this property in Listener
#   configuration elements:
#
#    <Set name="Port"><SystemProperty name="jetty.port" default="8080"/></Set>
#
#   Note: that the config file could ignore this property simply by saying:
#
#    <Set name="Port">8080</Set>
#
# JETTY_RUN
#   Where the jetty.pid file should be stored. It defaults to the
#   first available of /var/run, /usr/var/run, and /tmp if not set.
#  
# JETTY_PID
#   The Jetty PID file, defaults to $JETTY_RUN/jetty.pid
#   
# JETTY_ARGS
#   The default arguments to pass to jetty.
#
# JETTY_USER
#   if set, then used as a username to run the server as
#

usage()
{
    echo "Usage: ${0##*/} [-d] {start|stop|run|restart|check|supervise} [ CONFIGS ... ] "
    exit 1
}

[ $# -gt 0 ] || usage


##################################################
# Some utility functions
##################################################
findDirectory()
{
  local L OP=$1
  shift
  for L in "$@"; do
    [ "$OP" "$L" ] || continue 
    printf %s "$L"
    break
  done 
}

running()
{
  local PID=$(cat "$1" 2>/dev/null) || return 1
  kill -0 "$PID" 2>/dev/null
}

readConfig()
{
  (( DEBUG )) && echo "Reading $1.."
  source "$1"
}



##################################################
# Get the action & configs
##################################################
CONFIGS=()
NO_START=0
DEBUG=0

while [[ $1 = -* ]]; do
  case $1 in
    -d) DEBUG=1 ;;
  esac
  shift
done
ACTION=$1
shift

##################################################
# Read any configuration files
##################################################
for CONFIG in /etc/default/jetty{,7} $HOME/.jettyrc; do
  if [ -f "$CONFIG" ] ; then 
    readConfig "$CONFIG"
  fi
done


##################################################
# Set tmp if not already set.
##################################################
TMPDIR=${TMPDIR:-/tmp}

##################################################
# Jetty's hallmark
##################################################
JETTY_INSTALL_TRACE_FILE="etc/jetty.xml"


##################################################
# Try to determine JETTY_HOME if not set
##################################################
if [ -z "$JETTY_HOME" ] 
then
  JETTY_SH=$0
  case "$JETTY_SH" in
    /*)   ;;
    ./*)  ;;
    *)    JETTY_SH=./$JETTY_SH ;;
  esac
  JETTY_HOME=${JETTY_SH%/*/*}

  if [ ! -f "${JETTY_SH%/*/*}/$JETTY_INSTALL_TRACE_FILE" ]
  then 
    JETTY_HOME=
  fi
fi


##################################################
# if no JETTY_HOME, search likely locations.
##################################################
if [ -z "$JETTY_HOME" ] ; then
  STANDARD_LOCATIONS=(
        "/usr/share"
        "/usr/share/java"
        "${HOME}"
        "${HOME}/src"
        "${HOME}/opt"
        "/opt"
        "/java"
        "/usr/local"
        "/usr/local/share"
        "/usr/local/share/java"
        "/home"
        )
  JETTY_DIR_NAMES=(
        "jetty-7"
        "jetty7"
        "jetty-7.*"
        "jetty"
        "Jetty-7"
        "Jetty7"
        "Jetty-7.*"
        "Jetty"
        )
        
  for L in "${STANDARD_LOCATIONS[@]}"
  do
    for N in "${JETTY_DIR_NAMES[@]}"
    do
      JETTY_HOME=("$L/"$N)
      if [ ! -d "$JETTY_HOME" ] || [ ! -f "$JETTY_HOME/$JETTY_INSTALL_TRACE_FILE" ]
      then
        JETTY_HOME=
      fi
    done

    [ "$JETTY_HOME" ] && break
  done
fi


##################################################
# No JETTY_HOME yet? We're out of luck!
##################################################
if [ -z "$JETTY_HOME" ]; then
  echo "** ERROR: JETTY_HOME not set, you need to set it or install in a standard location" 
  exit 1
fi

cd "$JETTY_HOME"
JETTY_HOME=$PWD


#####################################################
# Check that jetty is where we think it is
#####################################################
if [ ! -r "$JETTY_HOME/$JETTY_INSTALL_TRACE_FILE" ] 
then
  echo "** ERROR: Oops! Jetty doesn't appear to be installed in $JETTY_HOME"
  echo "** ERROR:  $JETTY_HOME/$JETTY_INSTALL_TRACE_FILE is not readable!"
  exit 1
fi

##################################################
# Try to find this script's configuration file,
# but only if no configurations were given on the
# command line.
##################################################
if [ -z "$JETTY_CONF" ] 
then
  if [ -f /etc/jetty.conf ]
  then
    JETTY_CONF=/etc/jetty.conf
  elif [ -f "$JETTY_HOME/etc/jetty.conf" ]
  then
    JETTY_CONF=$JETTY_HOME/etc/jetty.conf
  fi
fi

##################################################
# Get the list of config.xml files from jetty.conf
##################################################
if [ -z "$CONFIGS" ] && [ -f "$JETTY_CONF" ] && [ -r "$JETTY_CONF" ] 
then
  while read -r CONF
  do
    if expr "$CONF" : '^#' >/dev/null ; then
      continue
    fi

    if [ ! -r "$CONF" ] 
    then
      echo "** WARNING: Cannot read '$CONF' specified in '$JETTY_CONF'" 
    elif [ -f "$CONF" ] 
    then
      # assume it's a configure.xml file
      CONFIGS+=("$CONF")
    elif [ -d "$CONF" ] 
    then
      # assume it's a directory with configure.xml files
      # for example: /etc/jetty.d/
      # sort the files before adding them to the list of CONFIGS
      for file in "$CONF/"*.xml
      do
        if [ -r "$FILE" ] && [ -f "$FILE" ] 
        then
          CONFIGS+=("$FILE")
        else
          echo "** WARNING: Cannot read '$FILE' specified in '$JETTY_CONF'" 
        fi
      done
    else
      echo "** WARNING: Don''t know what to do with '$CONF' specified in '$JETTY_CONF'" 
    fi
  done < "$JETTY_CONF"
fi

#####################################################
# Find a location for the pid file
#####################################################
if [ -z "$JETTY_RUN" ] 
then
  JETTY_RUN=$(findDirectory -w /var/run /usr/var/run /tmp)
fi

#####################################################
# Find a PID for the pid file
#####################################################
if [ -z "$JETTY_PID" ] 
then
  JETTY_PID="$JETTY_RUN/jetty.pid"
fi


##################################################
# Check for JAVA_HOME
##################################################
if [ -z "$JAVA_HOME" ]
then
  # If a java runtime is not defined, search the following
  # directories for a JVM and sort by version. Use the highest
  # version number.

  # Java search path
  JAVA_LOCATIONS=(
      "/usr/java"
      "/usr/bin"
      "/usr/local/bin"
      "/usr/local/java"
      "/usr/local/jdk"
      "/usr/local/jre"
      "/usr/lib/jvm"
      "/opt/java"
      "/opt/jdk"
      "/opt/jre"
      )
  IFS=: read JVERSION JAVA < <(
    for N in java jdk jre
    do
      for L in "${JAVA_LOCATIONS[@]}"
      do
        [ -d "$L" ] || continue 
        find "$L" -name "$N" ! -type d ! -path '*threads*' | while read JAVA; do
          [ -x "$JAVA" ] || continue

          JAVA_VERSION=$("$JAVA" -version 2>&1) || continue
          IFS='"_' read _ JAVA_VERSION _ <<< "$JAVA_VERSION"

          [ "$JAVA_VERSION" ] || continue
          expr "$JAVA_VERSION" '<' '1.2' >/dev/null && continue

          echo "$JAVA_VERSION:$JAVA"
        done
      done
    done | sort)

  JAVA_HOME=${JAVA%/*}
  while [ "$JAVA_HOME" ] && [ ! -f "$JAVA_HOME/lib/tools.jar" ] ; do
    JAVA_HOME=${JAVA_HOME%/*}
  done
  if [ -z "$JAVA_HOME" ]
  then
    echo "** ERROR: Java installation at '$JAVA' doesn't appear to be valid or complete." 
    exit 1
  fi

  (( DEBUG )) && echo "Found java '$JAVA' at '$JAVA_HOME'"
fi


##################################################
# Determine which JVM of version >1.5
# Try to use JAVA_HOME
##################################################
if [ -z "$JAVA" ] && [ "$JAVA_HOME" ]
then
  if [ "$JAVACMD" ] 
  then
    JAVA="$JAVACMD" 
  else
    [ -x "$JAVA_HOME/bin/jre" -a ! -d "$JAVA_HOME/bin/jre" ] && JAVA=$JAVA_HOME/bin/jre
    [ -x "$JAVA_HOME/bin/java" -a ! -d "$JAVA_HOME/bin/java" ] && JAVA=$JAVA_HOME/bin/java
  fi
fi

if [ -z "$JAVA" ]
then
  echo "Cannot find a JRE or JDK. Please set JAVA_HOME to a >=1.5 JRE" 2>&2
  exit 1
fi

JAVA_VERSION=$("$JAVA" -version 2>&1) || continue
IFS='"_' read _ JAVA_VERSION _ <<< "$JAVA_VERSION"

#####################################################
# See if JETTY_PORT is defined
#####################################################
if [ "$JETTY_PORT" ] 
then
  JAVA_OPTIONS+=("-Djetty.port=$JETTY_PORT")
fi

#####################################################
# See if JETTY_LOGS is defined
#####################################################
if [ "$JETTY_LOGS" ]
then
  JAVA_OPTIONS+=("-Djetty.logs=$JETTY_LOGS")
fi

#####################################################
# Are we running on Windows? Could be, with Cygwin/NT.
#####################################################
case "`uname`" in
CYGWIN*) PATH_SEPARATOR=";";;
*) PATH_SEPARATOR=":";;
esac


#####################################################
# Add jetty properties to Java VM options.
#####################################################
JAVA_OPTIONS+=("-Djetty.home=$JETTY_HOME" "-Djava.io.tmpdir=$TMPDIR")

[ -f "$JETTY_HOME/etc/start.config" ] && JAVA_OPTIONS=("-DSTART=$JETTY_HOME/etc/start.config" "${JAVA_OPTIONS[@]}")

#####################################################
# This is how the Jetty server will be started
#####################################################

JETTY_START=$JETTY_HOME/start.jar
[ ! -f "$JETTY_START" ] && JETTY_START=$JETTY_HOME/lib/start.jar

START_INI=$(dirname $JETTY_START)/start.ini
[ -r "$START_INI" ] || START_INI=""

RUN_ARGS=("${JAVA_OPTIONS[@]}" -jar "$JETTY_START" $JETTY_ARGS "${CONFIGS[@]}")
RUN_CMD=("$JAVA" "${RUN_ARGS[@]}")

#####################################################
# Comment these out after you're happy with what 
# the script is doing.
#####################################################
if (( DEBUG ))
then
  echo "JETTY_HOME     =  $JETTY_HOME"
  echo "JETTY_CONF     =  $JETTY_CONF"
  echo "JETTY_RUN      =  $JETTY_RUN"
  echo "JETTY_PID      =  $JETTY_PID"
  echo "JETTY_ARGS     =  $JETTY_ARGS"
  echo "CONFIGS        =  ${CONFIGS[*]}"
  echo "JAVA_OPTIONS   =  ${JAVA_OPTIONS[*]}"
  echo "JAVA           =  $JAVA"
  echo "RUN_CMD        =  ${RUN_CMD}"
fi

##################################################
# Do the action
##################################################
case "$ACTION" in
  start)
    echo -n "Starting Jetty: "

    if (( NO_START )); then 
      echo "Not starting jetty - NO_START=1";
      exit
    fi

    if type start-stop-daemon > /dev/null 2>&1 
    then
      [ -z "$JETTY_USER" ] && JETTY_USER=$USER
      (( UID == 0 )) && CH_USER=-c$JETTY_USER
      if start-stop-daemon -S -p"$JETTY_PID" "$CH_USER" -d"$JETTY_HOME" -b -m -a "$JAVA" -- "${RUN_ARGS[@]}"
      then
        sleep 1
        if running "$JETTY_PID"
        then
          echo "OK"
        else
          echo "FAILED"
        fi
      fi

    else

      if [ -f "$JETTY_PID" ]
      then
        if running $JETTY_PID
        then
          echo "Already Running!"
          exit 1
        else
          # dead pid file - remove
          rm -f "$JETTY_PID"
        fi
      fi

      if [ "$JETTY_USER" ] 
      then
        touch "$JETTY_PID"
        chown "$JETTY_USER" "$JETTY_PID"
        # FIXME: Broken solution: wordsplitting, pathname expansion, arbitrary command execution, etc.
        su - "$JETTY_USER" -c "
          ${RUN_CMD[*]} &
          disown \$!
          echo \$! > '$JETTY_PID'"
      else
        "${RUN_CMD[@]}" &
        disown $!
        echo $! > "$JETTY_PID"
      fi

      echo "STARTED Jetty `date`" 
    fi

    ;;

  stop)
    echo -n "Stopping Jetty: "
    if type start-stop-daemon > /dev/null 2>&1; then
      start-stop-daemon -K -p"$JETTY_PID" -d"$JETTY_HOME" -a "$JAVA" -s HUP
      
      TIMEOUT=30
      while running "$JETTY_PID"; do
        if (( TIMEOUT-- == 0 )); then
          start-stop-daemon -K -p"$JETTY_PID" -d"$JETTY_HOME" -a "$JAVA" -s KILL
        fi

        sleep 1
      done

      rm -f "$JETTY_PID"
      echo OK
    else
      PID=$(cat "$JETTY_PID" 2>/dev/null)
      kill "$PID" 2>/dev/null
      
      TIMEOUT=30
      while running $JETTY_PID; do
        if (( TIMEOUT-- == 0 )); then
          kill -KILL "$PID" 2>/dev/null
        fi

        sleep 1
      done

      rm -f "$JETTY_PID"
      echo OK
    fi

    ;;

  restart)
    JETTY_SH=$0
    if [ ! -f $JETTY_SH ]; then
      if [ ! -f $JETTY_HOME/bin/jetty.sh ]; then
        echo "$JETTY_HOME/bin/jetty.sh does not exist."
        exit 1
      fi
      JETTY_SH=$JETTY_HOME/bin/jetty.sh
    fi

    "$JETTY_SH" stop "$@"
    "$JETTY_SH" start "$@"

    ;;

  supervise)
    #
    # Under control of daemontools supervise monitor which
    # handles restarts and shutdowns via the svc program.
    #
    exec "${RUN_CMD[@]}"

    ;;

  run|demo)
    echo "Running Jetty: "

    if [ -f "$JETTY_PID" ]
    then
      if running "$JETTY_PID"
      then
        echo "Already Running!"
        exit 1
      else
        # dead pid file - remove
        rm -f "$JETTY_PID"
      fi
    fi

    exec "${RUN_CMD[@]}"

    ;;

  check)
    echo "Checking arguments to Jetty: "
    echo "JETTY_HOME     =  $JETTY_HOME"
    echo "JETTY_CONF     =  $JETTY_CONF"
    echo "JETTY_RUN      =  $JETTY_RUN"
    echo "JETTY_PID      =  $JETTY_PID"
    echo "JETTY_PORT     =  $JETTY_PORT"
    echo "JETTY_LOGS     =  $JETTY_LOGS"
    echo "START_INI      =  $START_INI"
    echo "CONFIGS        =  ${CONFIGS[*]}"
    echo "JAVA_OPTIONS   =  ${JAVA_OPTIONS[*]}"
    echo "JAVA           =  $JAVA"
    echo "CLASSPATH      =  $CLASSPATH"
    echo "RUN_CMD        =  ${RUN_CMD[*]}"
    echo
    
    if [ -f "$JETTY_RUN/jetty.pid" ]
    then
      echo "Jetty running pid=$(< "$JETTY_RUN/jetty.pid")"
      exit 0
    fi
    exit 1

    ;;

  *)
    usage

    ;;
esac

exit 0
