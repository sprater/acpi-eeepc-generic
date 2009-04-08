#!/bin/bash
#
# Copyright 2009 Nicolas Bigaouette
# This file is part of acpi-eeepc-generic.
# http://code.google.com/p/acpi-eeepc-generic/
#
# acpi-eeepc-generic is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# acpi-eeepc-generic is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with acpi-eeepc-generic.  If not, see <http://www.gnu.org/licenses/>.


. /etc/conf.d/acpi-eeepc-generic.conf

[ ! -d "${EEEPC_VAR}/states" ] && mkdir -p ${EEEPC_VAR}/states

chmod a+w ${EEEPC_VAR}/states/* &> /dev/null

### Extract kernel version
KERNEL=`uname -r`
KERNEL=${KERNEL%%-*}
KERNEL_maj=${KERNEL%%\.*}
k=${KERNEL#${KERNEL_maj}.}
KERNEL_min=${k%%\.*}
k=${KERNEL#${KERNEL_maj}.${KERNEL_min}.}
KERNEL_rel=${k%%\.*}
k=${KERNEL#${KERNEL_maj}.${KERNEL_min}.${KERNEL_rel}}
KERNEL_patch=${k%%\.*}

### Some paths
rfkills_path="/sys/class/rfkill"
sys_path="/sys/devices/platform/eeepc"

### Maximum try for toggling. Should not be even needed
TOGGLE_MAX_TRY=3

### Generic notification function ###############################
function eeepc_notify {
    if [ "$NOTIFY" == "libnotify" ]; then
        send_libnotify "$1" "$2" "$3"
    elif [ "$NOTIFY" == "kdialog" ]; then
        send_kdialog "$1" "$2" "$3"
    elif [ "$NOTIFY" == "dzen" ]; then
        send_dzen "$1" "$2" "$3"
    fi
    logger "EeePC $EEEPC_MODEL: $1 ($2)"
}

### libnotify ###################################################
function send_libnotify() {
    if [ ! -e /usr/bin/notify-send ]; then
        logger "To use libnotify's OSD, please install 'notification-daemon'"
        echo   "To use libnotify's OSD, please install 'notification-daemon'"
        return 1
    fi
    icon=$2
    duration=$3
    [ "x$icon" == "x" ] && icon="eee"
    [ "x$duration" == "x" ] && duration=${NOTIFY_DURATION}
    cmd="/usr/bin/notify-send -i $icon -t $duration \"EeePC $EEEPC_MODEL\" \"$1\""
    send_generic "${cmd}"
}

### kdialog #####################################################
function send_kdialog() {
    if [ ! -e /usr/bin/kdialog ]; then
        logger "To use kdialog's OSD, please install 'kdebase'"
        echo   "To use kdialog's OSD, please install 'kdebase'"
        return 1
    fi
    duration=$3
    [ "x$duration" == "x" ] && duration=${NOTIFY_DURATION}
    duration=$(( $duration / 1000 ))
    cmd="/usr/bin/kdialog --passivepopup \"$1\" --title \"EeePC $EEEPC_MODEL\" $duration"
    send_generic "${cmd}"
}

### dzen ########################################################
function send_dzen() {
    if [ ! -e /usr/bin/dzen2 ]; then
        logger "To use dzen's OSD, please install 'dzen2'"
        echo   "To use dzen's OSD, please install 'dzen2'"
        return 1
    fi
    duration=$3
    [ "x$duration" == "x" ] && duration=${NOTIFY_DURATION}
    duration=$(( 5 * $duration / 1000 ))
    cmd="(echo \"$1\"; sleep $duration) | /usr/bin/dzen2 &"
    send_generic "${cmd}"
}

### Make sure GUI is run as user ################################
function send_generic() {
    if [ "x$UID" == "x0" ]; then
        /bin/su $user --login -c "${@}"
    else
        #bash -c "${@}"
        eval "${@}"
    fi
}

### Print all commands in an array ##############################
function print_commands() {
    cmds=( "$@" )
    cmds_num=${#cmds[@]}
    [ "$cmds_num" == "0" ] && echo "NONE"
    for ((i=0;i<${cmds_num};i++)); do
        c=${cmds[${i}]}
        echo "#$(($i+1)): $c"
    done
}

### Execute all commands in an array ############################
function execute_commands() {
    [ "x$EEEPC_CONF_DONE" == "xno" ] && eeepc_notify "PLEASE EDIT YOUR CONFIGURATION FILE:
/etc/conf.d/acpi-eeepc-generic.conf" stop 20000
    cmds=( "$@" )
    cmds_num=${#cmds[@]}
    for ((i=0;i<${cmds_num};i++)); do
        c=${cmds[${i}]}
        if [ "${c:0:1}" == "@" ]; then
            logger "execute_commands (as user $user) #$(($i+1)): $c"
            echo "execute_commands (as user $user) #$(($i+1)): $c"
            /bin/su $user --login -c "${c:1} &"
        else
            logger "execute_commands #$(($i+1)): $c"
            echo "execute_commands #$(($i+1)): $c"
            eval ${c}
        fi
    done
}

### Load modules ################################################
function load_modules() {
    modules=( "$@" )
    modules_num=${#modules[@]}
    for ((i=0;i<${modules_num};i++)); do
        m=${modules[${i}]}
        /sbin/modprobe ${m}
        #sleep 1
    done
}

### Unload modules ##############################################
function unload_modules() {
    modules=( "$@" )
    modules_num=${#modules[@]}
    for ((i=0;i<${modules_num};i++)); do
        m="${modules[${i}]}"
        # Only the first word is the module, the rest might are options,
        # which are irrevelant in unloading the module.
        /sbin/modprobe -r ${m%% *}
        #sleep 1
    done
}

### Verify if volume if muted ###################################
function volume_is_mute() {
    # 1 is true, 0 is false
    on_off=`amixer get ${ALSA_MUTE_MIXER} | grep -A 1 -e Mono | grep Playback | awk '{print ""$4""}'`
    is_muted=0
    [ "$on_off" == "[off]" ] && is_muted=1
    echo $is_muted
}

### Return the volume level #####################################
function get_volume() {
    echo `amixer get ${ALSA_MAIN_MIXER} | grep -A 1 -e Mono | grep Playback | awk '{print ""$5""}' | sed -e "s|\[||g" -e "s|]||g" -e "s|\%||g"`
}

### Return the mixer ############################################
function get_output_mixers() {
    mixers=`amixer scontrols | awk '{print ""$4""}' | sed -e "s|'||g" -e "s|,0||g"`
    i=0
    for m in ${mixers}; do
        # If not a capture, its a playback
        if [ "`amixer sget $m | grep -i capture`" == "" ]; then
            output_mixers[i]=$m
            i=$((i+1))
        fi
    done
    #echo "mixers: ${mixers}"
    #echo "nb: ${#mixers[@]}"
    #echo "output_mixers: ${output_mixers[@]}"
    #echo "nb: ${#output_mixers[@]} $i"
    echo ${output_mixers[@]}
}

### Get the model name ##########################################
function get_model() {
    if [ -z "${EEEPC_MODEL}" ]; then
        echo "EEEPC_MODEL=\"$(dmidecode -s system-product-name | sed 's/[ \t]*$//')\"" >> /etc/conf.d/acpi-eeepc-generic.conf
        CPU=NONE
        grep_cpu=`grep Celeron /proc/cpuinfo`
        [ "x$grep_cpu" != "x" ] && CPU="Celeron"
        grep_cpu=`grep Atom /proc/cpuinfo`
        [ "x$grep_cpu" != "x" ] && CPU="Atom"
        echo "EEEPC_CPU=\"$CPU\"" >> /etc/conf.d/acpi-eeepc-generic.conf
    fi
}

### Return brightness level percentage ##########################
function brightness_get_percentage() {
    actual_brightness=`cat /sys/class/backlight/eeepc/actual_brightness`
    maximum_brightness=`cat /sys/class/backlight/eeepc/max_brightness`
    echo $((10000*$actual_brightness / (100*$maximum_brightness) ))
}

### Set the brightness level percentage #########################
function brightness_set_percentage() {
    #actual_brightness=`cat /sys/class/backlight/eeepc/actual_brightness`
    maximum_brightness=`cat /sys/class/backlight/eeepc/max_brightness`
    to_set=$(( $1 * $maximum_brightness / 100 ))
    #echo "max = $maximum_brightness"
    #echo "now = $actual_brightness"
    #echo "1 = $1"
    #echo "to set = $to_set"
    echo $to_set > /sys/class/backlight/eeepc/brightness
}

### Save brightness #############################################
function save_brightness() {
    cat /sys/class/backlight/eeepc/brightness > ${EEEPC_VAR}/states/brightness
}

### Restore brightness ##########################################
function restore_brightness() {
    cat ${EEEPC_VAR}/states/brightness > /sys/class/backlight/eeepc/brightness
}

### Set brightness (absolute value) #############################
function brightness_set_absolute() {
    echo $1 > /sys/class/backlight/eeepc/brightness
}

### Get direction of brightness change ##########################
function brightness_find_direction() {
    actual_brightness=`cat /sys/class/backlight/eeepc/actual_brightness`
    previous_brightness=`cat ${EEEPC_VAR}/states/brightness`
    [ "x$previous_brightness" == "x" ] && previous_brightness=$actual_brightness
    to_return=""
    [ $actual_brightness -lt $previous_brightness ] && to_return="down"
    [ $actual_brightness -gt $previous_brightness ] && to_return="up"
    echo $actual_brightness > ${EEEPC_VAR}/states/brightness
    echo $to_return
}

### Print generic debug information #############################
function print_generic_debug() {
    echo "DEBUG: EeePC model: $EEEPC_MODEL ($EEEPC_CPU)"
    echo "DEBUG: BIOS version: `dmidecode | grep -A 5 BIOS | grep Version | awk '{print ""$2""}'`"
    echo "DEBUG: Running kernel: `uname -a`"
    if [ -e /usr/bin/pacman ]; then
        echo "DEBUG: Installed kernel(s):"
        /usr/bin/pacman -Qs kernel26
    fi

    if [ ${#DRIVERS[@]} -gt 1 ]; then
        plural="s"
    else
        plural=""
    fi
    echo "DEBUG ($0): Driver${plural}:     ${DRIVERS[@]} (${#DRIVERS[@]})"
    echo "DEBUG ($0): is enabled:    ${IS_ENABLED}"

    if [ "x${INTERFACE}" != "x" ]; then
    echo "DEBUG ($0): interface:     ${INTERFACE}"
    fi

    if [ "${SYS_IS_PRESENT}" == "yes" ]; then
    echo "DEBUG ($0): /sys device:   ${SYS_DEVICE}"
    echo "DEBUG ($0): /sys state:    ${SYS_STATE}"
    else
    echo "DEBUG ($0): /sys device is not present"
    fi

    if [ "${RFKILL_IS_PRESENT}" == "yes" ]; then
    echo "DEBUG ($0): rfkill switch: ${RFKILL_SWITCH}"
    echo "DEBUG ($0): rfkill state:  ${RFKILL_STATE}"
    else
    echo "DEBUG ($0): rfkill switch is not present"
    fi

    echo "DEBUG ($0): COMMANDS_PRE_UP:"
    print_commands "${COMMANDS_PRE_UP[@]}"
    echo "DEBUG ($0): COMMANDS_POST_UP:"
    print_commands "${COMMANDS_POST_UP[@]}"
    echo "DEBUG ($0): COMMANDS_PRE_DOWN:"
    print_commands "${COMMANDS_PRE_DOWN[@]}"
    echo "DEBUG ($0): COMMANDS_POST_DOWN:"
    print_commands "${COMMANDS_POST_DOWN[@]}"

    if [ "x${INTERFACE}" != "x" ]; then
        interface_notify_msg="
interface: ${INTERFACE}"
    fi

    if [ "${SYS_IS_PRESENT}" == "yes" ]; then
    SYS_MESSAGE="/sys device: ${SYS_DEVICE}
/sys state: ${SYS_STATE}"
    else
    SYS_MESSAGE="/sys device is not present"
    fi

    if [ "${RFKILL_IS_PRESENT}" == "yes" ]; then
    RFKILL_MESSAGE="rfkill switch: ${RFKILL_SWITCH}
rfkill state:  ${RFKILL_STATE}"
    else
    RFKILL_MESSAGE="rfkill switch is not present"
    fi

    eeepc_notify "${NAME}
Driver${plural}: ${DRIVERS[@]}
is enabled: ${IS_ENABLED} ${interface_notify_msg}
${SYS_MESSAGE}
${RFKILL_MESSAGE}" ${ICON} 10000
}

### Toggle the device on and off ################################
function device_toggle {
    if [ "${IS_ENABLED}" == "yes" ]; then
        device_off 1
    else
        device_on 1
    fi
}

### Restore a device ############################################
function device_restore() {
    if [ "${SAVED_STATE}" == "1" ]; then
        device_on 1 0
    else
        device_off 1 0
    fi
}

### Check /sys interface ########################################
function check_sys_interface() {
    SYS_DEVICE="${sys_path}/${SYS_NAME}"
    if [ -e ${SYS_DEVICE} ]; then
        SYS_IS_PRESENT="yes"
        # Get sys state (0 = card off, 1 = card on)
        SYS_STATE=$(cat ${SYS_DEVICE})
    else
        # Some models do not have any such device (1000HE)
        SYS_IS_PRESENT="no"
        SYS_STATE=""
    fi
}

### Check rfkill switch #########################################
function check_rfkill_switch() {
    if [ -e ${rfkills_path} ]; then
        # Default to the second one
        rfkill="rfkill1"
        for r in `/bin/ls ${rfkills_path}/`; do
            name=`cat ${rfkills_path}/$r/name`
            [ "$name" == "eeepc-${NAME_SMALL}" ] && rfkill=$r
        done
        RFKILL_IS_PRESENT="yes"
        RFKILL_SWITCH="${rfkills_path}/${rfkill}/state"
        # Get rfkill switch state (0 = card off, 1 = card on)
        RFKILL_STATE=$(cat ${RFKILL_SWITCH})
    else
        # rfkill disabled/not present
        RFKILL_IS_PRESENT="no"
        RFKILL_SWITCH=""
        RFKILL_STATE=0
    fi
}

### Detect if card is enabled or disabled #######################
function detect_if_enabled() {
    if [[ "${SYS_IS_PRESENT}" == "yes" && "${RFKILL_IS_PRESENT}" == "yes" ]]; then
        # Both are present, no problem!

        # States of both should match. Else we have a problem...
        if   [[ "${SYS_STATE}" == "1" && "${RFKILL_STATE}" == "1" ]]; then
            IS_ENABLED="yes"
        elif [[ "${SYS_STATE}" == "0" && "${RFKILL_STATE}" == "0" ]]; then
            IS_ENABLED="no"
        else
            msg="ERROR in $0: /sys interface state (${SYS_STATE}) and rfkill switch state (${RFKILL_STATE}) do not match!"
            logger "$msg"
            eeepc_notify "$msg" stop
            exit 1
        fi
    else
        # One of the two is not present. Just get the state of the other
        if   [[ "${SYS_IS_PRESENT}"    == "yes" && "${SYS_STATE}"    == "1" ]]; then
            IS_ENABLED="yes"
        elif [[ "${RFKILL_IS_PRESENT}" == "yes" && "${RFKILL_STATE}" == "1" ]]; then
            IS_ENABLED="yes"
        else
            IS_ENABLED="no"
        fi
    fi
}

### Load saved state from file ##################################
function load_saved_state() {
    SAVED_STATE_FILE=${EEEPC_VAR}/states/${NAME_SMALL}
    if [ -e $SAVED_STATE_FILE ]; then
        SAVED_STATE=$(cat $SAVED_STATE_FILE)
    else
        SAVED_STATE=0
    fi
}

### Turn of device ##############################################
function device_on {
    # First argument ($1):  Number of times the funciton has been called
    # Second argument ($2): Should we show notifications?

    # Check if 2nd argument to given to function is "0" and disable
    # notifications,
    show_notifications=1
    [ "$2" == "0" ] && show_notifications=0

    [ "${IS_ENABLED}" == "yes" ] && \
        eeepc_notify "${NAME} already turned on!" ${ICON} && \
            return 0

    [ "$show_notifications" == "1" ] && \
        eeepc_notify "Turning ${NAME} on..." ${ICON}

    # Execute pre-up commands just once
    [ $1 -eq 1 ] && \
        execute_commands "${COMMANDS_PRE_UP[@]}"

    # Enable rfkill switch (which might fail on less then 2.6.29)
    if [ "${RFKILL_IS_PRESENT}" == "yes" ]; then
        echo 1 > ${RFKILL_SWITCH}

        if [ ${KERNEL_rel} -lt 29 ]; then
            s="rfkill switch usage might fail on kernel lower than 2.6.29"
            logger "$s"
            echo "$s"
        fi
    fi

    if [ "x$INTERFACE" != "x" ]; then
        # Put interface up and wait 1 second
        eval ${INTERFACE_UP}
        sleep 1
    fi

    # Load module(s)
    load_modules "${DRIVERS[@]}"

    success=$?
    if [ $success ]; then
        # If successful, enable card
        [ "${SYS_IS_PRESENT}" == "yes" ] && \
            echo 1 > ${SYS_DEVICE}

        # Save the card state
        echo 1 > $SAVED_STATE_FILE

        # Execute post-up commands
        execute_commands "${COMMANDS_POST_UP[@]}"

        [ "$show_notifications" == "1" ] && \
            eeepc_notify "${NAME} is now on" ${ICON}
    else
        # If module loading was not successful...

        [ "$show_notifications" == "1" ] && \
            eeepc_notify "Could not enable ${NAME}" stop

        # Try again
        if [ $1 -lt $TOGGLE_MAX_TRY ]; then
            [ "$show_notifications" == "1" ] && \
                eeepc_notify "Trying again in 2 second ($(($1+1)) / $TOGGLE_MAX_TRY)" ${ICON}
            sleep 2
            device_on $(($1+1)) $show_notifications
        fi
    fi
}

### Turn off device #############################################
function device_off {
    # First argument ($1):  Number of times the funciton has been called
    # Second argument ($2): Should we show notifications?

    # Check if 2nd argument to given to function is "0" and disable
    # notifications,
    show_notifications=1
    [ "$2" == "0" ] && show_notifications=0

    [ "${IS_ENABLED}" == "no" ] && \
        eeepc_notify "${NAME} already turned off!" ${ICON} && \
            return 0

    [ "$show_notifications" == "1" ] && \
        eeepc_notify "Turning ${NAME} off..." ${ICON}

    # Execute pre-down commands just once
    [ $1 -eq 1 ] && \
        execute_commands "${COMMANDS_PRE_DOWN[@]}"

    if [ "x$INTERFACE" != "x" ]; then
        # Put interface down and wait 1 second
        eval ${INTERFACE_DOWN}
        sleep 1
    fi

    # Unload module
    unload_modules "${DRIVERS[@]}"

    success=$?
    if [ $success ]; then
        # If successful...
        if [ "${RFKILL_IS_PRESENT}" == "yes" ]; then
            # ...and rfkill switch exists

            # Disable the card via rfkill switch
            echo 0 > ${RFKILL_SWITCH}

            if [ ${KERNEL_rel} -lt 29 ]; then
                s="rfkill switch usage might fail on kernel lower than 2.6.29"
                logger "$s"
                echo "$s"
            fi
        fi

        # If /sys device exists, disable it too
        [ "${SYS_IS_PRESENT}" == "yes" ] && \
            echo 0 > ${SYS_DEVICE}

        # Save the card states
        echo 0 > $SAVED_STATE_FILE

        # Execute post-down commands
        execute_commands "${COMMANDS_POST_DOWN[@]}"

        [ "$show_notifications" == "1" ] && \
            eeepc_notify "${NAME} is now off" ${ICON}
    else
        # If module unloading unsuccessful, try again

        [ "$show_notifications" == "1" ] && \
            eeepc_notify "Could not disable ${NAME}" stop

        if [ $1 -lt $TOGGLE_MAX_TRY ]; then
            [ "$show_notifications" == "1" ] && \
                eeepc_notify "Trying again in 2 second ($(($1+1)) / $TOGGLE_MAX_TRY)" ${ICON}
            sleep 2
            device_off $(($1+1)) $show_notifications
        fi
    fi
}

### Get username ################################################
if [ -S /tmp/.X11-unix/X0 ]; then
    export DISPLAY=:0

    # Detect logged in user by using "who"
    user=$(who | sed -n '/ (:0[\.0]*)$\| :0 /{s/ .*//p;q}')
    # If there is a space in $user, autodetection failed, so clear it.
    [ "x`echo $user | grep ' '`" != "x" ] && user=""

    # If autodetection fails, try another way...
    # Take first reported by "who"
    #[ "x$user" == "x" ] && user=$(who | head -1 | awk '{print $1}')
    # If there is a space in $user, autodetection failed, so clear it.
    #[ "x`echo $user | grep ' '`" != "x" ] && user=""

    # If autodetection fails, try another way...
    # Take users reported by "who" and return uniq values
    [ "x$user" == "x" ] && user=$(who | awk '{print $1}' | uniq)
    # If there is a space in $user, autodetection failed, so clear it.
    [ "x`echo $user | grep ' '`" != "x" ] && user=""

    # If autodetection fails, try another way...
    # Get user who executed startx. Might not work if a login
    # manager (GDM,KDM,etc.) is used.
    [ "x$user" == "x" ] && user=$(ps aux | grep '[x]init /home' | awk '{print $1}' | head -1)
    # If there is a space in $user, autodetection failed, so clear it.
    [ "x`echo $user | grep ' '`" != "x" ] && user=""

    # If autodetection fails, fallback to default user
    # set in /etc/conf.d/acpi-eeepc-generic.conf
    [ "x$user" == "x" ] && user=$XUSER

    # As a last resort, check all processes and their owning user,
    # filtering known users.
    [ "x$user" == "x" ] && user=$(ps aux | awk '{print ""$1""}' | \
        sort | uniq | \
        grep -v \
            -e avahi -e bin -e dbus -e ftp-e hal -e nobody \
            -e ntp -e nx -e policykit -e privoxy -e root \
            -e tor -e USER
        )
    # If there is a space in $user, autodetection failed, so clear it.
    [ "x`echo $user | grep ' '`" != "x" ] && user=""

    # If user is _still_ empty, notify the user to set XUSER in
    # configuration file.
    [ "x$user" == "x" ] && \
        eeepc_notify "User autodetection failed. Please edit \
your configuration file (/etc/conf.d/acpi-eeepc-generic.conf) \
and set XUSER variable to your username." stop 20000

    # If user is detected correctly (not empty), set variables
    # accordingly.
    if [ "x$user" != "x" ]; then
        home=$(getent passwd $user | cut -d: -f6)
        XAUTHORITY=$home/.Xauthority
        [ -f $XAUTHORITY ] && export XAUTHORITY
    fi
fi

### End of file #################################################

