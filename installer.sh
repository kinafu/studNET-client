#!/bin/sh
# Install script for permanent login at the Studentenwerk Leipzig internet connection "StudNET"
# insert your data, which you got from your facility manager
studnetNr=""
studnetPass=""

# ServerIP should stay the same for everyone, I obtained the IP from page 17 from https://www.studentenwerk-leipzig.de/sites/default/files/media/files/user_manual_studnet_01.08.2017_en.pdf
# be careful
studnetServerIP="139.18.143.253"

#install routine, do not change lines below

edit_studnetNr() {
	echo "StudNET tenant number/Mieternummer: "
	read -r studnetNr
}
edit_studnetPass() {
	echo "StudNET password: "
	stty -echo	#posix compliant replacement for read -s
	read -r studnetPass
	stty echo
}
edit_studnetServerIP() {
	echo "Only change this, if you obtained a different IP from the user manual."
	echo "Instruction manual from the Studentenwerk may also be found online."
	echo "Enter StudNET Server IP or just press [ENTER] to skip."
	read -r temp
	case "$temp" in
	"\n" ) ;;
	* ) studnetServerIP="$temp";;
	esac
}
connect_studnet() {
	sshpass -p $studnetPass \
	ssh -q -t -t -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
		$studnetNr@$studnetServerIP \
		> /dev/null &  #starting ssh in background
}


if [ "$(id -u)" -ne 0 ]; then
	echo "Sorry, you need to run the installer as root"
	exit 1
fi

if [ -e /etc/debian_version ]; then
	OS="debian"
elif [ -e /etc/fedora-release ]; then
	OS=fedora
elif [ -e /etc/centos-release ] || [ -e /etc/redhat-release ] || [ -e /etc/system-release ]; then
	OS=centos
elif [ -e /etc/arch-release ]; then
	OS=arch
else
	echo "Looks like you are not running this installer on a Debian, Ubuntu, CentOS or ArchLinux system."
	echo "No problem, just make sure you have installed ssh and sshpass."
	echo "Are ssh and sshpass installed on your system? Please type [y]es or [n]o and press [ENTER]: "
	read -r choice
  case "$choice" in
	y|Y|Yes|yes ) ;;
	n|N ) echo "Leaving now." && exit 4;;
	  * ) ;;
  esac
fi

#ask for login credentials, if not entered at the beginning of the script
[ -z $studnetNr ] && edit_studnetNr;
[ -z $studnetPass ] && edit_studnetPass;
[ -z $studnetServerIP ] && edit_studnetServerIP;

echo "Now I will test the connection with StudNET Server. "
echo "Press [Enter] to continue."
read -r choice

# "ping" StudNET Server to check basical connection
while ! nc -z -w 4 $studnetServerIP 22; do
  echo "Cannot reach StudNET server."
  echo "- Make sure you're connected to the right LAN port in your appartment."
  echo "  In each room only ONE of the two available LAN ports work."
  echo "- Check your network settings on the router or on your device."
  echo "- You need to configure standard gateway, DHCP, ... ON YOUR OWN."
  echo "  This has to be done in the router's settings, if you are using one."
  echo "- It's possible, that the StudNET Server IP changed."
  echo ""
  echo "To re-attempt connection, press [ENTER]. 
  echo "To enter a new Server IP type \"ip\"."
  echo "Otherwise type \"exit\"."
  echo ""
  read -r choice
  case "$choice" in
	#y|Y|Yes|yes )
	#	;;
	ip|\"ip\"|\"ip\". )
		edit_studnetServerIP ;;
	exit)
		echo "Leaving now." && exit 4
  esac
done

# login at StudNET server
return_code=0
while ([ "$return_code" -eq 0 ]) do
	connect_studnet
	pid=$!  #getting pid of ssh
	# evaluate connection (is alive?)
	sleep 4
	ps -p $pid >/dev/null
	return_code=$?  #if ssh session still alive exitcode 0, ssh process found, connection should have been succesful
	kill $pid >/dev/null 2>&1

  if  [ "$return_code" -gt 0 ]; then
	echo "\n"
	echo "Wrong password/username."
	echo "To try again press [Enter]."
	echo "To ignore unsucessful login type \"ignore\""
	read -r choice
	case "$choice" in
	 ignore|\"ignore\"|no|n|N)
		choice="ignore"
		;;
	 * )
		edit_studnetNr
		edit_studnetPass
		;;
	esac
  fi
done

if [ "$choice" != "ignore" ]; then
  echo "Successfully logged in."
fi

echo "We will now update your installed packages and download new required packages."

#connecting to StudNET server for internet for downloads
connect_studnet
pid=$!


#determine raspberry pi
if [ "$(cat /proc/cpuinfo | grep 'Hardware' | awk '{print $3}')" = "BCM2835" ]; then
	raspi="true"
	#add watchdog package to download list
	additional_packages="watchdog"
fi

#install packages
return_code=0
if ! ps -p $pid >/dev/null; then
	# if ssh still connected/ if "everything fine" :)
	echo "no connection via StudNET"
	exit 4
else
	case "$OS" in
		'debian' )
			apt-get update && apt-get dist-upgrade
			apt-get install openssh-client sshpass ca-certificates curl unattended-upgrades $additional_packages -y
			return_code="$?"

			#enable auto updates
			sudo dpkg-reconfigure --priority=low unattended-upgrades #automatically install security updates for the OS (not for StudNET client)
			if [ "$return_code" -gt 0 ]; then
				echo "Installing required packages failed. Aborting..."
				exit 4
			fi
			;;
		'arch' )
			pacman -Syu openssh sshpass ca-certificates curl $additional_packages --needed --noconfirm
			[ "$?" -ne $return_code ] && return_code="$?"
			;;
		'centos'|'fedora' )
			dnf update -y
			dnf install openssh-clients sshpass ca-certificates curl dnf-automatic $additional_packages -y
			return_code="$?"
			#enable auto updates
			if [ $return_code -eq 0 ]; then
			  if [ "$( cat /etc/fedora-release | awk '{print $3}' )" -le 25 ]; then
					systemctl enable dnf-automatic.timer
			  fi
				if [ "$( cat /etc/fedora-release | awk '{print $3}' )" -ge 26 ]; then
					systemctl enable dnf-automatic-install.timer
				fi
			fi
			if [ "$(service yum-updatesd status > /dev/null)" -eq 0 ]; then
				return_code=1
				echo "Outdated auto update system detected. (yum-updates)"
				echo "Please migrate to dnf-automatic."
			fi
			if [ "$return_code" -gt 0 ]; then
				echo "Installing required packages failed. Aborting..."
				exit 4
			fi

		;;
	esac
fi
kill $pid >/dev/null #kill ssh, which we needed for internet for downloads

# firewall allow outgoing, should be standard,
# following lines only needed, if you think, you messed around with firewall (which shouldn't be necessary :)

#sudo apt-get -y install ufw
#sudo ufw default allow outgoing
#sudo ufw enable

# watchdog to autostart in case of system crash (only for raspi)

if [ $raspi = true ]; then
	echo "\n"
	echo "Installing kernel module, in order to restart raspi at crucial crashes."
	modprobe bcm2835_wdt
	echo "bcm2835_wdt" | sudo tee -a /etc/modules
	# edit watchdog config through uncommenting lines
	sed -i '/^#.*max-load-1/s/^#//' /etc/watchdog.conf
	sed -i '/^#.*watchdog-device/s/^#//' /etc/watchdog.conf
	# fix bug in Raspbian stretch
	if [ "$(lsb_release -a 2>/dev/null | grep raspbian 2> /dev/null 1>&2)" = true ]; then
		"WantedBy=multi-user.target" >> /lib/systemd/system/watchdog.service
	fi
	# add watchdog to startup applications
	systemctl enable watchdog
	service watchdog start
fi

# write studnet .sh script with individual username and password
touch /usr/local/bin/studnet.sh
sudo chmod u+rwx /usr/local/bin/studnet.sh

cat <<'EOF' | sudo tee /usr/local/bin/studnet.sh > /dev/null
#!/bin/sh
HOST=https://bing.com

while true; do
	curl --head --silent --connect-timeout 2 "$HOST" > /dev/null
	error_code=$?

	if [ "$error_code" -gt 0 ]; then
		echo "Pinging $HOST was unsucessful." 1>&2
		echo "Reconnecting now"
		# kill 1st background job in current session, which is our (old) ssh session
		kill %1 > /dev/null 2>&1
		sleep 3
		sshpass -p "$studnetPass" ssh -t -t -o StrictHostKeyChecking=no "$studnetNr"@139.18.143.253 &
		sleep 2
	else
		sleep 10
	fi
done
EOF
echo "sshpass -p $studnetPass ssh -t -t -o StrictHostKeyChecking=no $studnetNr@$studnetServerIP &" | sudo tee -a /usr/local/bin/studnet.sh > /dev/null
cat <<'EOF' | sudo tee -a /usr/local/bin/studnet.sh > /dev/null
				sleep 2
		done
done
EOF

# create studnet service daemon, with autostart on system startup
touch /etc/systemd/system/studnet.service
# write service file, which executes studnet.sh script
cat <<'EOF' | sudo tee /etc/systemd/system/studnet.service > /dev/null
[Unit]
Description=StudNET permanent login
After=network.target

[Service]
ExecStart=/usr/local/bin/studnet.sh
SyslogIdentifier=StudNET Client
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable studnet.service
service studnet start && echo "StudNET Client up and running. You may go ahead. Auto-Login is turned on."
