#!/bin/sh
# Install script for permanent login at the Studentenwerk Leipzig internet connection "StudNET"
# insert your data, which you got from your facility manager
studnetPass=""
studnetNr=""

#be careful here!! ServerIP should stay be the same for everyone, I got the IP from page 17 from https://www.studentenwerk-leipzig.de/sites/default/files/media/files/user_manual_studnet_01.08.2017_en.pdf
studnetServerIP="139.18.143.253"

edit_credentials() {
        if [ -z $studnetNr ]; then
                echo "Please enter your StudNET tenant number/Mieternummer and press [ENTER]: "
                read -r studnetNr
        fi

        if [ -z $studnetPass ]; then
                echo "Please enter your password for the studNET Client and press [ENTER]: "
                stty -echo
                read -r studnetPass
                stty echo
        fi
        if [ -z $studnetPass ] && [ $1 = 1 ]; then
                echo "Please enter the studNET authentification server IP adress and press [ENTER]: "
                read -r studnetServerIP
        fi
}

#ask for login credentials, if not entered at the beginning of the script
edit_credentials

echo "Please make sure, your machine is connected to the internet. The script will download requiered packages."
echo "Press [ENTER] to continue."
read -r blah

# update OS
sudo apt-get update 
sudo apt-get -y dist-upgrade 

# install sshpass
sudo apt-get -y install sshpass 

# firewall
#sudo apt-get -y install ufw
#sudo ufw allow 22
#sudo ufw enable

echo "Now testing Studnet Client Login once"
if sshpass -p $studnetPass ssh -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 $studnetNr@$studnetServerIP exit ;
then
        echo "Successfully logged in."
else
        echo "Login was not successful with your login credentials. Do you want to re-enter your tenant number, password and IP?"
        echo "Please type [y]/n and press [ENTER]: "
        read -r choice
        case "$choice" in 
          y|Y ) edit_credentials 1;;
          n|N ) ;;
            * ) edit_credentials 1;;
        esac
fi



# fail2ban
sudo apt-get install fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo service fail2ban restart

# watchdog
sudo apt-get install watchdog
sudo modprobe bcm2835_wdt
echo "bcm2835_wdt" | sudo tee -a /etc/modules

# edit watchdog config through uncommenting lines
sudo sed -i '/^#.*max-load-1/s/^#//' /etc/watchdog.conf
sudo sed -i '/^#.*watchdog-device/s/^#//' /etc/watchdog.conf
# add watchdog to startup applications
sudo systemctl enable watchdog
sudo service watchdog start

# studnet .sh script
sudo touch /usr/local/bin/studnet.sh 
sudo chmod u+rwx /usr/local/bin/studnet.sh
cat <<'EOF' | sudo tee -a /usr/local/bin/studnet.sh
#!/bin/bash
while true
do
EOF
echo "sshpass -p $studnetPass ssh -t -o StrictHostKeyChecking=no $studnetNr@$studnetServerIP" | sudo tee -a /usr/local/bin/studnet.sh
cat <<'EOF' | sudo tee -a /usr/local/bin/studnet.sh
\"done\"
sleep 5
done
EOF


# add the sh script to startup
cat <<'EOF' | sudo tee -a /etc/systemd/system/studnet.service
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

# activate auto updates
sudo apt-get -y install unattended-upgrades apt-listchanges
sudo dpkg-reconfigure --priority=low unattended-upgrades
