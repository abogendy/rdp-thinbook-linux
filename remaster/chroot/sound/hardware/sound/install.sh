#!/bin/bash
PROG_DIR=$(printf %q "$(readlink -e $(dirname $0))")
SCRIPTS_DIR=$(printf %q "${PROG_DIR}/scripts")

# Check that required scripts are present
if [ ! -d ${PROG_DIR}/UCM ]; then
    echo "Missing dir: ${PROG_DIR}/UCM"
    exit 1
fi
if [ ! -f ${PROG_DIR}/rdp-sound-modules.conf ]; then
    echo "Missing file: ${PROG_DIR}/rdp-sound-modules.conf"
    exit 1
fi

if [ ! -f ${SCRIPTS_DIR}/bytcr_rt5651_sound.service ]; then
    echo "Missing file: ${SCRIPTS_DIR}/bytcr_rt5651_sound.service"
    exit 1
fi

if [ ! -f ${PROG_DIR}/setup_bytcr_rt5651_asound_state.sh ]; then
    echo "Missing file: ${PROG_DIR}/setup_bytcr_rt5651_asound_state.sh"
    exit 1
fi

\cp -fr ${PROG_DIR}/UCM/* /usr/share/alsa/ucm/
# bytcr-rt5651 is updated, but if kernel is 4.13 or older, we use
# old-byt-cr-rt5651 to keep old behavior unchanged - i.e. with kernels
# newer than 4.13, the new UCM files will be used
if [ -d /usr/share/alsa/ucm/bytcr-rt5651 -a -d /usr/share/alsa/ucm/old-bytcr-rt5651 ]; then
    MAJ=$(uname -r | cut -d'.' -f1)
    MIN=$(uname -r | cut -d'.' -f2)i
    if [ \( $MAJ -eq 4 -a $MIN -gt 13 \) -o \( $MAJ -gt 4 \) ]; then
        mv /usr/share/alsa/ucm/bytcr-rt5651 /usr/share/alsa/ucm/new-bytcr-rt5651
        mv /usr/share/alsa/ucm/old-bytcr-rt5651 /usr/share/alsa/ucm/bytcr-rt5651
    fi
fi

# If pulseaudio version is >= 1:10.0-2ubuntu3, disable snd_hdmi_lpe_audio
# module by blacklisting it - since loading that module makes pulseaudio
# fail to start
PULSEAUDIO_VER=$(dpkg-query -W --showformat '${Version}' pulseaudio)
LARGEST_VER=$((echo $PULSEAUDIO_VER; echo 1:10.0-2ubuntu3) | sort -V | tail -1)
if [ "$LARGEST_VER" = "$PULSEAUDIO_VER" ]; then
    if [ -f ${PROG_DIR}/rdp-sound-blacklist-hdmi.conf ]; then
        echo "Blacklisting snd_hdmi_lpe_audio"
        cat ${PROG_DIR}/rdp-sound-blacklist-hdmi.conf >> ${PROG_DIR}/rdp-sound-modules.conf
    else
        echo "Missing file: ${PROG_DIR}/rdp-sound-blacklist-hdmi.conf"
        exit 1
    fi
fi
\cp -fr ${PROG_DIR}/rdp-sound-modules.conf /etc/modprobe.d/


# On RDP Thinbook, set the default output (sink)
# alsa_output.platform-bytcht_es8316.HiFi__hw_bytchtes8316__sink : 14-inch RDP Thinbook
# alsa_output.platform-bytcr_rt5651.HiFi__hw_bytcrrt5651__sink : 11-inch RDP Thinbook
# We only need to do this if we have NOT blacklisted snd_hdmi_lpe_audio in
# rdp-sound-modules.conf
grep -q '[ ]*blacklist[ ][ ]*snd_hdmi_lpe_audio' ${PROG_DIR}/rdp-sound-modules.conf
if [ $? -ne 0 ]; then
    OUTPUTS="alsa_output.platform-bytcht_es8316.HiFi__hw_bytchtes8316__sink alsa_output.platform-bytcr_rt5651.HiFi__hw_bytcrrt5651__sink"
    if [ -f /etc/pulse/default.pa ]; then
        (
            echo ""
            echo "# On RDP Thinbook, set the default output (sink)"
            echo "# Sinks are tried IN ORDER. If only ONE of these sinks are available,"
            echo "# then that sink will be the default output"
            echo "# If more than one of these sinks are available, then the LAST one"
            echo "# will be the default output"
            echo "#"
            for output in $OUTPUTS
            do
                echo "set-default-sink $output"
            done
        ) >> /etc/pulse/default.pa
    else
        echo "Missing file: /etc/pulse/default.pa"
    fi
fi

\cp -f ${SCRIPTS_DIR}/bytcr_rt5651_sound.service /etc/systemd/system/
mkdir -p /etc/systemd/system/sound.target.wants
\rm -f /etc/systemd/system/sound.target.wants/bytcr_rt5651_sound.service

ln -s /etc/systemd/system/bytcr_rt5651_sound.service /etc/systemd/system/sound.target.wants/
