#!/data/data/com.termux/files/usr/bin/bash

: ${DIALOG=dialog}
: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_ESC=255}
INTERACTIVE_TITLE="Home Assistant Voice Termux Installer"

MODE=""
WORKING_DIR=$(pwd)

# Installer
INSTALL_EVENTS=""
NO_AUTOSTART=""
NO_INPUT=""
SKIP_UNINSTALL=0
INSTALL_WYOMING=1
INSTALL_OWW=1
INTERACTIVE=1

# Config
SELECTED_WAKE_WORD="ok_nabu"
SELECTED_DEVICE_NAME=""
HASS_TOKEN=""
HASS_URL="http://homeassistant.local:8123"
WYOMING_SATELLITE_FLAGS="--debug"

# Wake sounds
SELECTED_WAKE_SOUND="./sounds/awake.wav"
SELECTED_DONE_SOUND="./sounds/done.wav"
SELECTED_TIMER_DONE_SOUND="./sounds/timer_finished.wav"
SELECTED_TIMER_REPEAT="5 0.5"

for i in "$@"; do
  case $i in
    --wake-word=*)
      SELECTED_WAKE_WORD="${i#*=}"
      shift
      ;;
    --device-name=*)
      SELECTED_DEVICE_NAME="${i#*=}"
      shift
      ;;
    --wake-sound=*)
      SELECTED_WAKE_SOUND="${i#*=}"
      shift
      ;;
    --done-sound=*)
      SELECTED_DONE_SOUND="${i#*=}"
      shift
      ;;
    --timer-finished-sound=*)
      SELECTED_TIMER_DONE_SOUND="${i#*=}"
      shift
      ;;
    --timer-finished-repeat=*)
      SELECTED_TIMER_REPEAT="${i#*=}"
      shift
      ;;
    --hass-token=*)
      HASS_TOKEN="${i#*=}"
      shift
      ;;
    --hass-url=*)
      HASS_URL="${i#*=}"
      shift
      ;;
    --install)
      MODE="INSTALL"
      shift
      ;;
    --uninstall)
      MODE="UNINSTALL"
      shift
      ;;
    --configure)
      MODE="CONFIGURE"
      shift
      ;;
    --no-autostart)
      NO_AUTOSTART=1
      shift
      ;;
    --skip-cleanup)
      SKIP_UNINSTALL=1
      shift
      ;;
    --skip-wyoming)
      INSTALL_WYOMING=0
      shift
      ;;
    --skip-wakeword)
      INSTALL_OWW=0
      shift
      ;;
    --install-events)
      INSTALL_EVENTS=1
      shift
      ;;
    -q)
      NO_INPUT=1
      shift
      ;;
    -i)
      INTERACTIVE=1
      shift
      ;;
    -*|--*)
      echo "Unknown option $i"
      exit 1
      ;;
    *)
      ;;
  esac
done

interactive_prompts () {
    ### Prompt to select options to install
    INSTALL_WYOMING=0
    INSTALL_OWW=0
    INSTALL_EVENTS=0
    MODE="INSTALL"
    declare -a INSTALL_OPTS=($($DIALOG --backtitle "$INTERACTIVE_TITLE" \
    --clear \
	--title "Install Options" \
    --checklist "Select options to install" 15 90 5 \
            1   "Core Wyoming Satellite service." ON \
            2   "OpenWakeWord to trigger the Assist pipeline locally on device." ON \
            3   "Event forwarder to expose Wyoming Events into Home Assistant." OFF 2>&1 >/dev/tty))

    for sel in "${INSTALL_OPTS[@]}"; do
        case "$sel" in
            1) INSTALL_WYOMING=1;;
            2) INSTALL_OWW=1;;
            3) INSTALL_EVENTS=1;;
            *) echo "Unknown option!";;
        esac
    done

    if $DIALOG --stdout --title "Autostart" \
            --backtitle "$INTERACTIVE_TITLE" \
            --yesno "Enable related services to start automatically on boot?" 7 60; then
        NO_AUTOSTART=0
        $DIALOG --title "Autostart" --backtitle "$INTERACTIVE_TITLE" --msgbox "Autostart will be enabled" 6 44
    else
        NO_AUTOSTART=1
        $DIALOG --title "Autostart" --backtitle "$INTERACTIVE_TITLE" --msgbox "You will need to start services manually" 6 44
    fi

    if [ "$INSTALL_WYOMING" = "1" ]; then
        $DIALOG --title "Wyoming Configuration" --backtitle "$INTERACTIVE_TITLE" --msgbox "Satellite will be installed" 6 44
        SELECTED_WAKE_WORD=$($DIALOG --stdout --title "Wyoming Configuration" \
            --backtitle "$INTERACTIVE_TITLE" \
            --radiolist "Wakeword" 50 50 5 \
            "alexa" "Alexa" OFF \
            "ok_nabu" "Ok Nabu" ON \
            "hey_mycroft" "Hey Mycroft" OFF \
            "hey_jarvis" "Hey Jarvis" OFF \
            "hey_rhasspy" "Hey Rhasspy" OFF)
        SELECTED_DEVICE_NAME=$($DIALOG --stdout --title "Wyoming Configuration" --backtitle "$INTERACTIVE_TITLE" --inputbox "Enter a name for your device\nIt must not include spaces if the event forwarder is being installed\nExample: wyoming_kitchen_assistant" 15 50)
        WYOMING_SATELLITE_FLAGS=$($DIALOG --stdout --title "Wyoming Configuration" --backtitle "$INTERACTIVE_TITLE" --inputbox "Enter additional Wyoming Satellite startup flags" 15 50 "$WYOMING_SATELLITE_FLAGS")
    fi

    if [ "$INSTALL_EVENTS" = "1" ]; then
        $DIALOG --title "Events Configuration" --backtitle "$INTERACTIVE_TITLE" --msgbox "Events will be installed\nThe following prompts will ask for details about your Home Assistant install" 15 50
        HASS_URL=$($DIALOG --stdout --title "Events Configuration" --backtitle "$INTERACTIVE_TITLE" --inputbox "Enter the URL of your Home Assistant install" 15 50 "$HASS_URL")
        HASS_TOKEN=$($DIALOG --stdout --title "Events Configuration" --backtitle "$INTERACTIVE_TITLE" --inputbox "Enter the acces token from Home Assistant\nThis can be copied into this prompt." 15 50)
    fi
}

interactive_post_install () {
    MESSAGE=$(cat << EOF
Install is now complete, the rest of the configuration can be performed in the Home Assistant UI
-----
Setup the Wyoming platform using the Android device's IP address with
Port: 10700 (Wyoming Satellite)
If you configured the event forwarder, these will be available under 'wyoming_*'
-----
Device options can now be set in the Home Assistant UI
-----
Recommended device settings*
-----
Lenovo ThinkSmart View
Mic Volume: 5.0
Noise Suppression Level: Medium
-----
Surface Go 2 (BlissOS 15)
Mic Volume: 3.0
Noise Suppression Level: Medium
-----
Press enter to exit
EOF
)
    $DIALOG --title "Installation Completed" --backtitle "$INTERACTIVE_TITLE" --msgbox "$MESSAGE" 20 60
    clear
}

preinstall () {
    echo "Running pre-install"
    echo "Enter home directory"
    cd $HOME

    touch wyoming.conf

    echo "Update packages and index"
    pkg up

    echo "Ensure Python + pip is available..."
    if ! command -v python3 > /dev/null 2>&1; then
        echo "Installing python..."
        pkg install python python-pip -y
        if ! command -v python3 > /dev/null 2>&1; then
            echo "ERROR: Failed to install python3" >&2
            exit 1
        fi
    fi

    echo "Ensure git is available..."
    if ! command -v git > /dev/null 2>&1; then
        echo "Installing git..."
        pkg install git -y
        if ! command -v git > /dev/null 2>&1; then
            echo "ERROR: Failed to install git" >&2
            exit 1
        fi
    fi

    echo "Ensure Termux Services is available..."
    if ! command -v sv-enable > /dev/null 2>&1; then
        echo "Installing service bus..."
        pkg install termux-services -y
        if ! command -v sv-enable > /dev/null 2>&1; then
            echo "ERROR: Failed to install termux-services" >&2
            exit 1
        else
            echo "Termux Services has been installed. Restart Termux to continue."
            exit 1
        fi
    fi

    echo "Ensure termux-api is available..."
    if ! command -v termux-microphone-record > /dev/null 2>&1; then
        echo "Installing termux-api..."
        pkg install termux-api -y
        if ! command -v termux-microphone-record > /dev/null 2>&1; then
            echo "ERROR: Failed to install termux-api (termux-microphone-record not found)" >&2
            exit 1
        fi
    fi

    echo "Ensure sox is available..."
    if ! command -v rec > /dev/null 2>&1; then
        echo "Installing sox..."
        pkg install sox -y
        if ! command -v rec > /dev/null 2>&1; then
            echo "ERROR: Failed to install sox (rec not found)" >&2
            exit 1
        fi
        if ! command -v play > /dev/null 2>&1; then
            echo "ERROR: Failed to install sox (play not found)" >&2
            exit 1
        fi
    fi

    if [ "$SKIP_UNINSTALL" = "0" ]; then
        echo "Clean up potential garbage that might otherwise get in the way..."
        cleanup
    fi

    echo "Installing Wyoming CLI"
    cp $WORKING_DIR/scripts/wyoming-cli $PREFIX/bin/wyoming-cli
    if [ "$INSTALL_OWW" = "0" ]; then sed -i '/sv\-enable\ wyoming\-wakeword/d' $PREFIX/bin/wyoming-cli; fi
    if [ "$INSTALL_EVENTS" = "0" ]; then sed -i '/sv\-enable\ wyoming\-events/d' $PREFIX/bin/wyoming-cli; fi
    if [ "$INSTALL_WYOMING" = "0" ]; then sed -i '/sv\-enable\ wyoming\-satellite/d' $PREFIX/bin/wyoming-cli; fi
    chmod a+x $PREFIX/bin/wyoming-cli
}

install_events () {
    mkdir -p $HOME/wyoming-events
    cp $WORKING_DIR/wyoming-events.py $HOME/wyoming-events/wyoming-events.py
    echo "Configuring events"
    python3 -m pip install wyoming aiohttp # ensure required libs are installed
    make_service "wyoming-events" "wyoming-events-android"
    echo "EVENTS_ENABLED=true" >> $HOME/wyoming.conf
    echo "HASS_TOKEN=\"$HASS_TOKEN\"" >> $HOME/wyoming.conf
    echo "HASS_URL=\"$HASS_URL\"" >> $HOME/wyoming.conf
}

configure () {
    echo "Configuring Wyoming options..."
    echo "CUSTOM_DEV_NAME=\"$SELECTED_DEVICE_NAME\"" >> $HOME/wyoming.conf
    echo "WAKESOUND=\"$SELECTED_WAKE_SOUND\"" >> $HOME/wyoming.conf
    echo "DONESOUND=\"$SELECTED_DONE_SOUND\"" >> $HOME/wyoming.conf
    echo "TIMERFINISHEDSOUND=\"$SELECTED_TIMER_DONE_SOUND\"" >> $HOME/wyoming.conf
    echo "TIMERFINISHEDREPEAT=\"$SELECTED_TIMER_REPEAT\"" >> $HOME/wyoming.conf
    echo "WYOMING_SATELLITE_FLAGS=\"$WYOMING_SATELLITE_FLAGS\"" >> $HOME/wyoming.conf

    echo "Configuring OpenWakeWord..."
    # OWW
    echo "SELECTED_WAKE_WORD=\"$SELECTED_WAKE_WORD\"" >> $HOME/wyoming.conf
    if [ "$INSTALL_OWW" = "1" ]; then
        echo "OWW_ENABLED=true" >> $HOME/wyoming.conf
    else
        echo "OWW_ENABLED=" >> $HOME/wyoming.conf
    fi
}

cleanup () {
    echo "Stopping and killing remaining services"
    sv-disable wyoming-satellite
    sv-disable wyoming-wakeword
    sv-disable wyoming-events
    killall python3

    echo "Deleting files and directories related to the project..."
    rm -f $HOME/tmp.wav
    rm -f $HOME/pulseaudio-without-memfd.deb 
    rm -rf $HOME/wyoming-satellite
    rm -rf $HOME/wyoming-openwakeword

    echo "Removing services"
    rm -rf $PREFIX/var/service/wyoming-*

    if [ "$MODE" = "UNINSTALL" ]; then
        if command -v sv > /dev/null 2>&1; then
            echo "Would you like to disable wakelock autostart? [y/N]"
            read disable_autostart
            if [ "$disable_autostart" = "y" ] || [ "$disable_autostart" = "Y" ]; then
                rm -f $HOME/.termux/boot/services-autostart
            fi
        fi
    fi
}

uninstall () {
    echo "Uninstalling custom pulseaudio build if it is installed..."
    if command -v pulseaudio > /dev/null 2>&1; then
        export ARCH="$(termux-info | grep -A 1 "CPU architecture:" | tail -1)" 
        echo "Architecture: $ARCH"
        if [ "$ARCH" = "arm" ]; then
            pkg remove -y pulseaudio
        fi
    fi

    if [ "$MODE" = "UNINSTALL" ]; then
        if command -v sv > /dev/null 2>&1; then
            echo "Would you like to remove Termux Services? [y/N]"
            read remove_services
            if [ "$remove_services" = "y" ] || [ "$remove_services" = "Y" ]; then
                pkg uninstall termux-services -y
            fi
        fi
    fi
}

make_service () {
    # Helper to make a new service
    local SVC_NAME="$1"
    local SVC_RUN_FILE="$2"
    echo "Setting up $SVC_NAME service..."
    mkdir -p $PREFIX/var/service/$SVC_NAME/
    touch $PREFIX/var/service/$SVC_NAME/down # ensure the service does not start when we kill runsv
    mkdir -p $PREFIX/var/service/$SVC_NAME/log
    ln -sf $PREFIX/share/termux-services/svlogger $PREFIX/var/service/$SVC_NAME/log/run
    cp $WORKING_DIR/services/$SVC_RUN_FILE $PREFIX/var/service/$SVC_NAME/run
    chmod +x $PREFIX/var/service/$SVC_NAME/run
    echo "Installed $SVC_NAME service"
}

check_memfd_support () {
    KERNEL_MAJOR_VERSION="$(uname -r | awk -F'.' '{print $1}')"
    if [ $KERNEL_MAJOR_VERSION -le 3 ]; then
        echo "Your kernel is too old to support memfd."
        echo "Installing a custom build of pulseaudio that doesn't depend on memfd..."
        export ARCH="$(termux-info | grep -A 1 "CPU architecture:" | tail -1)"
        echo "Checking if pulseaudio is currently installed..."
        if command -v pulseaudio > /dev/null 2>&1; then
            echo "Uninstalling pulseaudio..."
            pkg remove pulseaudio -y
        fi
        echo "Ensure wget is available..."
        if ! command -v wget > /dev/null 2>&1; then
            echo "Installing wget..."
            pkg install wget -y
            if ! command -v wget > /dev/null 2>&1; then
                echo "ERROR: Failed to install wget" >&2
                exit 1
            fi
        fi
        echo "Downloading pulseaudio build that doesn't require memfd..."
        wget -O ./pulseaudio-without-memfd.deb "https://github.com/T-vK/pulseaudio-termux-no-memfd/releases/download/1.1.0/pulseaudio_17.0-2_${ARCH}.deb"
        echo "Installing the downloaded pulseaudio build..."
        pkg install ./pulseaudio-without-memfd.deb -y
        echo "Removing the downloaded pulseaudio build (not required after installation)..."
        rm -f ./pulseaudio-without-memfd.deb
    else
        if ! command -v pulseaudio > /dev/null 2>&1; then
            pkg install pulseaudio -y
        fi
    fi
}

install () {
    if [ "$NO_INPUT" = "" ]; then
        MESSAGE=$(cat << EOF
At the end of this process a full reboot is recommended, ensure your device is completely powered down before starting back up
This is to ensure that the require wakelocks will start correctly
EOF
)
        $DIALOG --backtitle "$INTERACTIVE_TITLE" --msgbox "$MESSAGE" 20 60
        clear
    fi

    if [ "$HASS_URL" = "" ] && [ "$INSTALL_EVENTS" = "1" ]; then
        echo "Missing --hass-url parameter"
        echo "This argument is required with --install-events"
        exit 2
    fi

    if [ "$HASS_TOKEN" = "" ] && [ "$INSTALL_EVENTS" = "1" ]; then
        echo "Missing --hass-token parameter"
        echo "This argument is required with --install-events"
        exit 2
    fi

    preinstall

    echo "Starting a wakelock"
    termux-wake-lock

    echo "Checking if Linux kernel supports memfd..."
    check_memfd_support

    if ! command -v pulseaudio > /dev/null 2>&1; then
        echo "ERROR: Failed to install pulseaudio..." >&2
        exit 1
    fi

    echo "Starting test recording to trigger mic permission prompt..."
    echo "(It might ask you for mic access now. Select 'Always Allow'.)"
    termux-microphone-record -f ./tmp.wav

    echo "Quitting the test recording..."
    termux-microphone-record -q

    echo "Deleting the test recording..."
    rm -f ./tmp.wav

    echo "Temporarily load PulseAudio module for mic access..."
    if ! pactl list short modules | grep "module-sles-source" ; then
        if ! pactl load-module module-sles-source; then
            echo "ERROR: Failed to load module-sles-source" >&2
        fi
    fi

    echo "Verify that there is at least one microphone detected..."
    if ! pactl list short sources | grep "module-sles-source.c" ; then
        echo "ERROR: No microphone detected" >&2
    fi

    if [ "$INSTALL_WYOMING" = "1" ]; then
        echo "Cloning Wyoming Satellite repo..."
        git clone https://github.com/rhasspy/wyoming-satellite.git

        echo "Enter wyoming-satellite directory..."
        cd wyoming-satellite
        git checkout 3576c0f

        echo "Injecting faulthandler" # https://community.home-assistant.io/t/how-to-run-wyoming-satellite-and-openwakeword-on-android/777571/101?u=11harveyj
        sed -i '/_LOGGER = logging.getLogger()/a import faulthandler, signal' wyoming_satellite/__main__.py
        sed -i '/import faulthandler, signal/a faulthandler.register(signal.SIGSYS)' wyoming_satellite/__main__.py

        echo "Running Wyoming Satellite setup script..."
        echo "This process may appear to hang on low spec hardware. Do not exit unless you are sure that that the process is no longer responding"
        ./script/setup

        echo "Setting up autostart..."
        mkdir -p $HOME/.termux/boot/
        cp $WORKING_DIR/boot/services-autostart $HOME/.termux/boot/
        chmod +x $HOME/.termux/boot/services-autostart

        make_service "wyoming-satellite" "wyoming-satellite-android"

        configure

        # events
        if [ "$INSTALL_EVENTS" = "1" ]; then
            echo "Events enabled"
            install_events
        fi

        echo "Wyoming service installed. Restarting runsv"
        killall runsv
        echo "Waiting for runsv to restart"
        sleep 5
        echo "Successfully installed and set up Wyoming Satellite"
    fi

    if [ "$INSTALL_OWW" = "1" ]; then
        echo "Selected $SELECTED_WAKE_WORD"
        echo "Ensure python-tflite-runtime, ninja and patchelf are installed..."
        pkg install python-tflite-runtime ninja patchelf -y

        echo "Cloning Wyoming OpenWakeWord repo..."
        cd $HOME
        git clone https://github.com/rhasspy/wyoming-openwakeword.git

        echo "Enter wyoming-openwakeword directory..."
        cd wyoming-openwakeword
        git checkout d8e9780

        echo "Allow system site packages in Wyoming OpenWakeWord setup script..."
        sed -i 's/\(builder = venv.EnvBuilder(with_pip=True\)/\1, system_site_packages=True/' ./script/setup

        echo "Running Wyoming OpenWakeWord setup script..."
        ./script/setup
        make_service "wyoming-wakeword" "wyoming-wakeword-android"
    fi

    if [ "$NO_AUTOSTART" != "0" ]; then
        echo "Starting services now..."
        killall python3 # ensure no processes are running before starting the service
        if [ "$INSTALL_OWW" = "1" ]; then sv-enable wyoming-wakeword; fi
        if [ "$INSTALL_EVENTS" = "1" ]; then sv-enable wyoming-events; fi
        if [ "$INSTALL_WYOMING" = "1" ]; then sv-enable wyoming-satellite; fi
    fi
}

if [ "$MODE" = "" ] && [ "$INTERACTIVE" = "1" ]; then
    preinstall
    interactive_prompts
fi

if [ "$MODE" = "INSTALL" ]; then

    install
    echo "Install complete"
    if [ "$INTERACTIVE" = "1" ]; then
        interactive_post_install
    fi
    exit 0
fi

if [ "$MODE" = "UNINSTALL" ]; then
    cleanup
    uninstall
    echo "Uninstall complete"
    exit 0
fi

if [ "$MODE" = "CONFIGURE" ]; then
    configure
    echo "Reconfiguration complete"
    exit 0
fi

echo "Invalid mode specified, one of --install or --uninstall or --configure is required"
exit 1
